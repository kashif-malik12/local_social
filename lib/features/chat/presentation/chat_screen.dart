import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
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
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();
  late final ScrollController _scrollCtrl;
  bool _showEmojiPicker = false;

  bool _loading = true;
  bool _sending = false;
  String? _error;

  List<Map<String, dynamic>> _messages = [];
  bool _hasOlderMessages = true;
  bool _loadingOlder = false;

  String _otherName = 'Chat';
  String? _otherUserId;
  XFile? _selectedImage;
  PlatformFile? _selectedFile;

  // Reply state
  Map<String, dynamic>? _replyToMessage; // {id, text, senderName}

  // Reactions: messageId → {count, liked_by_me}
  Map<String, Map<String, dynamic>> _reactions = {};

  RealtimeChannel? _msgChannel;

  @override
  void initState() {
    super.initState();
    _scrollCtrl = ScrollController()..addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _focusNode.dispose();
    final ch = _msgChannel;
    _msgChannel = null;
    if (ch != null) {
      _db.removeChannel(ch);
    }
    _textCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingOlder || !_hasOlderMessages) return;
    if (_scrollCtrl.position.pixels <= 200) {
      _loadOlderMessages();
    }
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
      limit: 50,
    );

    if (!mounted) return;
    setState(() {
      _messages = rows.reversed.toList();
      _hasOlderMessages = rows.length == 50;
    });
    await _loadReactions();
  }

  Future<void> _loadReactions() async {
    if (_messages.isEmpty) return;
    final ids = _messages
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .toList();
    if (ids.isEmpty) return;
    try {
      final rxns = await _service.fetchReactions(ids);
      if (!mounted) return;
      setState(() => _reactions = rxns);
    } catch (_) {}
  }

  Future<void> _toggleReaction(String messageId) async {
    try {
      await _service.toggleReaction(messageId);
      await _loadReactions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reaction error: $e')),
      );
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || !_hasOlderMessages) return;
    if (_messages.isEmpty) return;

    setState(() => _loadingOlder = true);
    try {
      final oldestCreatedAt = _messages.first['created_at'] as String?;
      final rows = await _service.getMessages(
        conversationId: widget.conversationId,
        limit: 50,
        beforeIso: oldestCreatedAt,
      );

      if (!mounted) return;
      setState(() {
        _messages = [...rows.reversed, ..._messages];
        _hasOlderMessages = rows.length == 50;
      });
      await _loadReactions();
    } catch (_) {
      // silently ignore
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
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
    final reply = _replyToMessage;

    _textCtrl.clear();
    setState(() {
      _selectedImage = null;
      _selectedFile = null;
      _replyToMessage = null;
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
          replyToId: reply?['id'] as String?,
          replyToText: reply?['text'] as String?,
          replyToSenderName: reply?['senderName'] as String?,
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

  void _showMessageActions(Map<String, dynamic> msg, ChatMessagePayload payload, bool isMe) {
    final messageId = msg['id']?.toString() ?? '';
    final previewText = payload.text.trim().isNotEmpty
        ? payload.text.trim()
        : payload.hasImage
            ? '📷 Photo'
            : '📎 File';
    final senderName = isMe ? 'You' : _otherName;
    final rxn = _reactions[messageId];
    final likedByMe = rxn?['liked_by_me'] == true;

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Reply'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _replyToMessage = {
                    'id': messageId,
                    'text': previewText,
                    'senderName': senderName,
                  };
                  if (_showEmojiPicker) _showEmojiPicker = false;
                });
                _focusNode.requestFocus();
              },
            ),
            ListTile(
              leading: Icon(
                likedByMe ? Icons.favorite : Icons.favorite_border,
                color: likedByMe ? Colors.red : null,
              ),
              title: Text(likedByMe ? 'Unlike' : 'Like'),
              onTap: () {
                Navigator.pop(context);
                if (messageId.isNotEmpty) _toggleReaction(messageId);
              },
            ),
          ],
        ),
      ),
    );
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

  void _openImageFullscreen(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildReplyBanner() {
    final reply = _replyToMessage;
    if (reply == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: Color(0xFF0F766E)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply['senderName'] ?? '',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F766E),
                  ),
                ),
                Text(
                  reply['text'] ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _replyToMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    bool isMe,
    ChatMessagePayload payload, {
    String? createdAt,
    String? readAt,
    int likeCount = 0,
    bool likedByMe = false,
  }) {
    final timeStr = _formatTime(createdAt);
    final seen = readAt != null;

    return Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 300),
          decoration: BoxDecoration(
            color: isMe
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Reply quote
              if (payload.hasReply) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF0F766E), width: 3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        payload.replyToSenderName ?? '',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      Text(
                        payload.replyToText ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
              if (payload.text.trim().isNotEmpty) Text(payload.text.trim()),
              if (payload.hasImage) ...[
                if (payload.text.trim().isNotEmpty) const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _openImageFullscreen(payload.imageUrl!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(payload.imageUrl!, width: 220, fit: BoxFit.cover),
                  ),
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
              // Timestamp + read receipt
              if (isMe) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (timeStr != null)
                      Text(
                        timeStr,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      seen ? Icons.done_all : Icons.done,
                      size: 14,
                      color: seen ? const Color(0xFF0F766E) : Colors.grey.shade500,
                    ),
                  ],
                ),
              ] else if (timeStr != null) ...[
                const SizedBox(height: 4),
                Text(
                  timeStr,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
        // Like count badge
        if (likeCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: const [
                  BoxShadow(color: Color(0x18000000), blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.favorite,
                    size: 12,
                    color: likedByMe ? Colors.red : Colors.grey.shade500,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$likeCount',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String? _formatTime(String? isoString) {
    if (isoString == null) return null;
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return null;
    }
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
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length + (_loadingOlder ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (_loadingOlder && i == 0) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Loading older messages...',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          final msgIndex = _loadingOlder ? i - 1 : i;
                          final m = _messages[msgIndex];
                          final senderId = m['sender_id'] as String?;
                          final isMe = senderId != null && senderId == myId;
                          final payload = ChatMessageCodec.decode(
                            (m['content'] as String?) ?? '',
                          );
                          final messageId = m['id']?.toString() ?? '';
                          final rxn = _reactions[messageId];

                          return GestureDetector(
                            onLongPress: () =>
                                _showMessageActions(m, payload, isMe),
                            child: Align(
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: _buildMessageBubble(
                                isMe,
                                payload,
                                createdAt: m['created_at'] as String?,
                                readAt: m['read_at'] as String?,
                                likeCount: (rxn?['count'] as int?) ?? 0,
                                likedByMe: rxn?['liked_by_me'] == true,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildReplyBanner(),
                          _buildAttachmentComposerPreview(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Emoji',
                                  onPressed: () {
                                    if (_showEmojiPicker) {
                                      _focusNode.requestFocus();
                                    } else {
                                      _focusNode.unfocus();
                                    }
                                    setState(() => _showEmojiPicker = !_showEmojiPicker);
                                  },
                                  icon: Icon(
                                    _showEmojiPicker
                                        ? Icons.keyboard
                                        : Icons.emoji_emotions_outlined,
                                  ),
                                ),
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
                                    focusNode: _focusNode,
                                    textInputAction: TextInputAction.send,
                                    onSubmitted: (_) => _send(),
                                    onTap: () {
                                      if (_showEmojiPicker) {
                                        setState(() => _showEmojiPicker = false);
                                      }
                                    },
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
                          if (_showEmojiPicker)
                            SizedBox(
                              height: 280,
                              child: EmojiPicker(
                                textEditingController: _textCtrl,
                                config: const Config(
                                  height: 280,
                                  emojiViewConfig: EmojiViewConfig(
                                    columns: 8,
                                    emojiSizeMax: 28,
                                  ),
                                  categoryViewConfig: CategoryViewConfig(
                                    initCategory: Category.SMILEYS,
                                  ),
                                ),
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
