import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/media_limits.dart';
import '../../../services/user_block_service.dart';
import '../../../widgets/chat_user_actions.dart';
import '../../../widgets/global_app_bar.dart';
import '../../../widgets/global_bottom_nav.dart';
import '../services/chat_attachment_service.dart';
import '../services/chat_message_codec.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;

  const ChatScreen({super.key, required this.conversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _db = Supabase.instance.client;
  late final ChatService _service = ChatService(_db);
  late final ChatAttachmentService _attachmentService =
      ChatAttachmentService(_db);
  final _textCtrl = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  bool _sending = false;
  String? _error;

  List<Map<String, dynamic>> _messages = [];

  String _otherName = 'Chat';
  String? _otherUserId;
  XFile? _selectedImage;
  PlatformFile? _selectedFile;

  RealtimeChannel? _msgChannel;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    final ch = _msgChannel;
    _msgChannel = null;
    if (ch != null) {
      _db.removeChannel(ch);
    }
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await _loadChatHeader();
      await _reloadMessages();
      await _service.markConversationRead(widget.conversationId);
      _subscribeMessagesRealtime();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChatHeader() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) throw Exception('Not logged in');

    final conv = await _db
        .from('conversations')
        .select('user1, user2')
        .eq('id', widget.conversationId)
        .single();

    final user1 = conv['user1'] as String;
    final user2 = conv['user2'] as String;
    final other = user1 == me ? user2 : user1;

    final prof = await _db
        .from('profiles')
        .select('full_name')
        .eq('id', other)
        .maybeSingle();

    final blocked = await UserBlockService(_db).isBlockedEitherWay(other);
    if (blocked) {
      throw Exception('Messaging is unavailable for this user.');
    }

    final fullName = (prof?['full_name'] as String?)?.trim();
    if (!mounted) return;

    setState(() {
      _otherUserId = other;
      _otherName = (fullName != null && fullName.isNotEmpty) ? fullName : 'Chat';
    });
  }

  Future<void> _reloadMessages() async {
    final rows = await _service.getMessages(
      conversationId: widget.conversationId,
      limit: 200,
    );

    if (!mounted) return;
    setState(() => _messages = rows.reversed.toList());
  }

  void _subscribeMessagesRealtime() {
    if (_msgChannel != null) return;

    _msgChannel = _db.channel('chat-${widget.conversationId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: widget.conversationId,
        ),
        callback: (_) async {
          await _reloadMessages();
          await _service.markConversationRead(widget.conversationId);
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: widget.conversationId,
        ),
        callback: (_) async {
          await _reloadMessages();
        },
      )
      ..subscribe();
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: MediaLimits.postImageQuality,
    );
    if (picked == null || !mounted) return;

    final size = await picked.length();
    if (!mounted) return;
    if (size > ChatAttachmentService.maxImageBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo must be 10 MB or smaller.')),
      );
      return;
    }

    setState(() => _selectedImage = picked);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty || !mounted) return;

    final picked = result.files.first;
    if (picked.size > ChatAttachmentService.maxFileBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File must be 10 MB or smaller.')),
      );
      return;
    }

    setState(() => _selectedFile = picked);
  }

  Future<void> _send() async {
    if (_otherUserId != null) {
      final blocked = await UserBlockService(_db).isBlockedEitherWay(_otherUserId!);
      if (blocked) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Messaging is unavailable for this user.')),
        );
        return;
      }
    }

    final text = _textCtrl.text.trim();
    if ((text.isEmpty && _selectedImage == null && _selectedFile == null) ||
        _sending) {
      return;
    }

    setState(() => _sending = true);
    final image = _selectedImage;
    final file = _selectedFile;

    _textCtrl.clear();
    setState(() {
      _selectedImage = null;
      _selectedFile = null;
    });

    try {
      String? imageUrl;
      String? fileUrl;
      String? fileName;

      if (image != null) {
        imageUrl = await _attachmentService.uploadImage(image);
      }
      if (file != null) {
        fileUrl = await _attachmentService.uploadFile(file);
        fileName = file.name;
      }

      await _service.sendMessage(
        conversationId: widget.conversationId,
        content: ChatMessageCodec.encode(
          text: text,
          imageUrl: imageUrl,
          fileUrl: fileUrl,
          fileName: fileName,
        ),
      );

      await _reloadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteConversation() async {
    try {
      await _service.deleteConversation(widget.conversationId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat deleted.')),
      );
      context.go('/chats');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildAttachmentComposerPreview() {
    if (_selectedImage == null && _selectedFile == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (_selectedImage != null)
            Chip(
              label: Text(_selectedImage!.name),
              avatar: const Icon(Icons.photo_outlined, size: 18),
              onDeleted: () => setState(() => _selectedImage = null),
            ),
          if (_selectedFile != null)
            Chip(
              label: Text(_selectedFile!.name),
              avatar: const Icon(Icons.attach_file, size: 18),
              onDeleted: () => setState(() => _selectedFile = null),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(bool isMe, ChatMessagePayload payload) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (payload.text.trim().isNotEmpty) Text(payload.text.trim()),
          if (payload.hasImage) ...[
            if (payload.text.trim().isNotEmpty) const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(payload.imageUrl!, width: 220, fit: BoxFit.cover),
            ),
          ],
          if (payload.hasFile) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _openExternal(payload.fileUrl!),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        payload.fileName?.trim().isNotEmpty == true
                            ? payload.fileName!.trim()
                            : 'Open file',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = _db.auth.currentUser?.id;

    return Scaffold(
      appBar: GlobalAppBar(
        title: _otherName,
        showBackIfPossible: true,
        homeRoute: '/feed',
        actions: [
          if ((_otherUserId ?? '').isNotEmpty)
            IconButton(
              tooltip: 'User options',
              onPressed: () => openChatUserActions(
                context: context,
                otherUserId: _otherUserId!,
                onBlocked: () async {
                  if (!mounted) return;
                  context.go('/chats');
                },
                onDeleteChat: _deleteConversation,
              ),
              icon: const Icon(Icons.more_vert),
            ),
        ],
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final m = _messages[i];
                          final senderId = m['sender_id'] as String?;
                          final isMe = senderId != null && senderId == myId;
                          final payload = ChatMessageCodec.decode(
                            (m['content'] as String?) ?? '',
                          );

                          return Align(
                            alignment:
                                isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: _buildMessageBubble(isMe, payload),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildAttachmentComposerPreview(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Add photo',
                                  onPressed: _sending ? null : _pickImage,
                                  icon: const Icon(Icons.photo_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Add file',
                                  onPressed: _sending ? null : _pickFile,
                                  icon: const Icon(Icons.attach_file),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _textCtrl,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    decoration: const InputDecoration(
                                      hintText: 'Message...',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: _sending ? null : _send,
                                  icon: _sending
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Icon(Icons.send),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
