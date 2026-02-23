import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/global_app_bar.dart';
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

  final _textCtrl = TextEditingController();

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _messages = [];

  // ✅ Header (other user)
  String? _otherUserId;
  String _otherName = 'Chat';

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
      await _loadChatHeader(); // ✅ get other name
      await _reloadMessages();
      await _service.markConversationRead(widget.conversationId);
      _subscribeMessagesRealtime();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadChatHeader() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) throw Exception('Not logged in');

    // 1) Fetch conversation
    final conv = await _db
        .from('conversations')
        .select('user1, user2')
        .eq('id', widget.conversationId)
        .single();

    final user1 = conv['user1'] as String;
    final user2 = conv['user2'] as String;

    // 2) Determine other user
    final other = (user1 == me) ? user2 : user1;
    _otherUserId = other;

    // 3) Fetch other user profile name
    final prof = await _db
        .from('profiles')
        .select('full_name')
        .eq('id', other)
        .maybeSingle();

    final fullName = (prof?['full_name'] as String?)?.trim();
    if (!mounted) return;

    setState(() {
      _otherName = (fullName != null && fullName.isNotEmpty) ? fullName : 'Chat';
    });
  }

  Future<void> _reloadMessages() async {
    final rows = await _service.getMessages(
      conversationId: widget.conversationId,
      limit: 200,
      beforeIso: null,
    );

    // RPC returns DESC; UI wants ASC
    final asc = rows.reversed.toList();

    if (!mounted) return;
    setState(() => _messages = asc);
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

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    _textCtrl.clear();

    try {
      await _service.sendMessage(
        conversationId: widget.conversationId,
        content: text,
      );

      // fallback (if realtime delayed)
      await _reloadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = _db.auth.currentUser?.id;

    return Scaffold(
      // ✅ Show other user's name on top
      appBar: GlobalAppBar(
        title: _otherName,
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
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
                          final content = (m['content'] as String?) ?? '';

                          return Align(
                            alignment:
                                isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.blue.withOpacity(0.15)
                                    : Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(content),
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _textCtrl,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _send(),
                                decoration: const InputDecoration(
                                  hintText: 'Message…',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _send,
                              icon: const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}