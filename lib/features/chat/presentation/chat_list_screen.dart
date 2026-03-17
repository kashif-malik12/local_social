import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/global_app_bar.dart';
import '../../../widgets/global_bottom_nav.dart';
import '../services/chat_message_codec.dart';
import '../services/chat_service.dart';
import '../services/offer_chat_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _service = ChatService(Supabase.instance.client);
  final _offerService = OfferChatService(Supabase.instance.client);

  final _chatComposerCtrl = TextEditingController();
  final _offerComposerCtrl = TextEditingController();

  bool _loading = true;
  bool _offerLoading = true;
  String? _error;
  String? _offerError;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _offerRows = [];

  String? _selectedConversationId;
  String _selectedConversationName = 'Chat';
  bool _selectedConversationLoading = false;
  String? _selectedConversationError;
  List<Map<String, dynamic>> _selectedConversationMessages = [];
  bool _sendingChat = false;

  String? _selectedOfferConversationId;
  String _selectedOfferTitle = 'Offer chat';
  String _selectedOfferMeta = '';
  bool _selectedOfferLoading = false;
  String? _selectedOfferError;
  List<Map<String, dynamic>> _selectedOfferMessages = [];
  bool _sendingOfferChat = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _chatComposerCtrl.dispose();
    _offerComposerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.getChatList();
      if (!mounted) return;
      setState(() => _rows = rows);
      await _ensureChatSelection();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadOffers() async {
    setState(() {
      _offerLoading = true;
      _offerError = null;
    });
    try {
      final rows = await _offerService.getChatList();
      if (!mounted) return;
      setState(() => _offerRows = rows);
      await _ensureOfferSelection();
    } catch (e) {
      if (!mounted) return;
      setState(() => _offerError = e.toString());
    } finally {
      if (mounted) setState(() => _offerLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _load(),
      _loadOffers(),
    ]);
  }

  Future<void> _ensureChatSelection() async {
    if (_rows.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedConversationId = null;
        _selectedConversationMessages = [];
      });
      return;
    }

    final selectedStillExists = _rows.any(
      (row) => (row['conversation_id'] as String?) == _selectedConversationId,
    );

    if (!selectedStillExists) {
      final first = _rows.first;
      await _selectChatConversation(first);
    }
  }

  Future<void> _ensureOfferSelection() async {
    if (_offerRows.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedOfferConversationId = null;
        _selectedOfferMessages = [];
      });
      return;
    }

    final selectedStillExists = _offerRows.any(
      (row) => (row['conversation_id'] ?? '').toString() == _selectedOfferConversationId,
    );

    if (!selectedStillExists) {
      await _selectOfferConversation(_offerRows.first);
    }
  }

  Future<void> _selectChatConversation(Map<String, dynamic> row) async {
    final convId = row['conversation_id'] as String;
    final name = (row['other_full_name'] as String?) ?? 'Unknown';

    setState(() {
      _selectedConversationId = convId;
      _selectedConversationName = name;
      _selectedConversationLoading = true;
      _selectedConversationError = null;
      _selectedConversationMessages = [];
    });

    try {
      final rows = await _service.getMessages(
        conversationId: convId,
        limit: 200,
        beforeIso: null,
      );
      await _service.markConversationRead(convId);
      if (!mounted || _selectedConversationId != convId) return;
      setState(() => _selectedConversationMessages = rows.reversed.toList());
    } catch (e) {
      if (!mounted || _selectedConversationId != convId) return;
      setState(() => _selectedConversationError = e.toString());
    } finally {
      if (mounted && _selectedConversationId == convId) {
        setState(() => _selectedConversationLoading = false);
      }
    }
  }

  Future<void> _selectOfferConversation(Map<String, dynamic> row) async {
    final convId = (row['conversation_id'] ?? '').toString();
    final postTitle = (row['post_title'] as String?) ?? 'Listing';
    final status = (row['current_offer_status'] as String?) ?? '';
    final amount = (row['current_offer_amount'] as num?)?.toDouble();

    final meta = <String>[
      if (status.isNotEmpty && status != 'none') status.toUpperCase(),
      if (amount != null) 'EUR ${amount.toStringAsFixed(2)}',
    ].join(' • ');

    setState(() {
      _selectedOfferConversationId = convId;
      _selectedOfferTitle = postTitle;
      _selectedOfferMeta = meta;
      _selectedOfferLoading = true;
      _selectedOfferError = null;
      _selectedOfferMessages = [];
    });

    try {
      final rows = await _offerService.getMessages(
        conversationId: convId,
        limit: 200,
      );
      await _offerService.markConversationRead(convId);
      if (!mounted || _selectedOfferConversationId != convId) return;
      setState(() => _selectedOfferMessages = rows.reversed.toList());
    } catch (e) {
      if (!mounted || _selectedOfferConversationId != convId) return;
      setState(() => _selectedOfferError = e.toString());
    } finally {
      if (mounted && _selectedOfferConversationId == convId) {
        setState(() => _selectedOfferLoading = false);
      }
    }
  }

  Future<void> _sendChatMessage() async {
    final convId = _selectedConversationId;
    final text = _chatComposerCtrl.text.trim();
    if (convId == null || text.isEmpty || _sendingChat) return;

    setState(() => _sendingChat = true);
    _chatComposerCtrl.clear();

    try {
      await _service.sendMessage(conversationId: convId, content: text);
      final selectedRow = _rows.cast<Map<String, dynamic>?>().firstWhere(
            (row) => (row?['conversation_id'] as String?) == convId,
            orElse: () => null,
          );
      if (selectedRow != null) {
        await _selectChatConversation(selectedRow);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingChat = false);
    }
  }

  Future<void> _sendOfferMessage() async {
    final convId = _selectedOfferConversationId;
    final text = _offerComposerCtrl.text.trim();
    if (convId == null || text.isEmpty || _sendingOfferChat) return;

    setState(() => _sendingOfferChat = true);
    _offerComposerCtrl.clear();

    try {
      await _offerService.sendMessage(conversationId: convId, content: text);
      final selectedRow = _offerRows.cast<Map<String, dynamic>?>().firstWhere(
            (row) => (row?['conversation_id'] ?? '').toString() == convId,
            orElse: () => null,
          );
      if (selectedRow != null) {
        await _selectOfferConversation(selectedRow);
      }
      await _loadOffers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    } finally {
      if (mounted) setState(() => _sendingOfferChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: GlobalAppBar(
          title: 'Messages',
          showBackIfPossible: true,
          homeRoute: '/feed',
          actions: [
            IconButton(
              onPressed: _refreshAll,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        bottomNavigationBar: const GlobalBottomNav(),
        body: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Chats'),
                Tab(text: 'Offers'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildNormalChatsTab(),
                  _buildOfferChatsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalChatsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;
        if (!isWide) return _buildNormalChatsMobile();

        return Row(
          children: [
            SizedBox(
              width: 340,
              child: _buildChatListPane(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _buildSelectedChatPane(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOfferChatsTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1000;
        if (!isWide) return _buildOfferChatsMobile();

        return Row(
          children: [
            SizedBox(
              width: 360,
              child: _buildOfferListPane(),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _buildSelectedOfferPane(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNormalChatsMobile() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_rows.isEmpty) return const Center(child: Text('No conversations yet'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _rows.length,
      itemBuilder: (context, i) {
        final r = _rows[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildChatListTile(
            row: r,
            selected: false,
            onTap: () => context.push('/chat/${r['conversation_id']}'),
          ),
        );
      },
    );
  }

  Widget _buildOfferChatsMobile() {
    if (_offerLoading) return const Center(child: CircularProgressIndicator());
    if (_offerError != null) return Center(child: Text(_offerError!));
    if (_offerRows.isEmpty) return const Center(child: Text('No offer chats yet'));

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _offerRows.length,
      itemBuilder: (context, i) {
        final r = _offerRows[i];
        final convId = (r['conversation_id'] ?? '').toString();
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildOfferListTile(
            row: r,
            selected: false,
            onTap: convId.isEmpty ? null : () => context.push('/offer-chat/$convId'),
          ),
        );
      },
    );
  }

  Widget _buildChatListPane() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_rows.isEmpty) return const Center(child: Text('No conversations yet'));

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        itemBuilder: (context, i) {
          final row = _rows[i];
          final selected = (row['conversation_id'] as String?) == _selectedConversationId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildChatListTile(
              row: row,
              selected: selected,
              onTap: () => _selectChatConversation(row),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOfferListPane() {
    if (_offerLoading) return const Center(child: CircularProgressIndicator());
    if (_offerError != null) return Center(child: Text(_offerError!));
    if (_offerRows.isEmpty) return const Center(child: Text('No offer chats yet'));

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _offerRows.length,
        itemBuilder: (context, i) {
          final row = _offerRows[i];
          final selected = (row['conversation_id'] ?? '').toString() == _selectedOfferConversationId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildOfferListTile(
              row: row,
              selected: selected,
              onTap: () => _selectOfferConversation(row),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChatListTile({
    required Map<String, dynamic> row,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final name = (row['other_full_name'] as String?) ?? 'Unknown';
    final last = ChatMessageCodec.previewText(
      (row['last_message'] as String?) ?? '',
    );
    final unread = (row['unread_count'] as num?)?.toInt() ?? 0;

    return Material(
      color: selected
          ? const Color(0xFFF4EBDD)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? const Color(0xFFCC7A00) : const Color(0xFFE6DDCE),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      last.isEmpty ? 'No messages yet' : last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD92D20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfferListTile({
    required Map<String, dynamic> row,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final postTitle = (row['post_title'] as String?) ?? 'Listing';
    final last = ChatMessageCodec.previewText(
      (row['last_message'] as String?) ?? '',
    );
    final unread = (row['unread_count'] as num?)?.toInt() ?? 0;
    final status = (row['current_offer_status'] as String?) ?? '';
    final amount = (row['current_offer_amount'] as num?)?.toDouble();

    final meta = <String>[
      if (status.isNotEmpty && status != 'none') status.toUpperCase(),
      if (amount != null) 'EUR ${amount.toStringAsFixed(2)}',
    ].join(' • ');

    return Material(
      color: selected
          ? const Color(0xFFF4EBDD)
          : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? const Color(0xFFCC7A00) : const Color(0xFFE6DDCE),
            ),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                child: Icon(Icons.local_offer_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      postTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (last.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        last,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD92D20),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedChatPane() {
    if (_rows.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }
    if (_selectedConversationId == null) {
      return const Center(child: Text('Select a conversation'));
    }
    if (_selectedConversationLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedConversationError != null) {
      return Center(child: Text(_selectedConversationError!));
    }

    return Container(
      color: const Color(0xFFFBF8F2),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFE6DDCE)),
              ),
            ),
            child: Text(
              _selectedConversationName,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          Expanded(
            child: _buildMessageList(_selectedConversationMessages),
          ),
          _buildComposer(
            controller: _chatComposerCtrl,
            hintText: 'Write a message...',
            sending: _sendingChat,
            onSend: _sendChatMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedOfferPane() {
    if (_offerRows.isEmpty) {
      return const Center(child: Text('No offer chats yet'));
    }
    if (_selectedOfferConversationId == null) {
      return const Center(child: Text('Select an offer chat'));
    }
    if (_selectedOfferLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedOfferError != null) {
      return Center(child: Text(_selectedOfferError!));
    }

    return Container(
      color: const Color(0xFFFBF8F2),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              border: const Border(
                bottom: BorderSide(color: Color(0xFFE6DDCE)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedOfferTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (_selectedOfferMeta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _selectedOfferMeta,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/offer-chat/$_selectedOfferConversationId'),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('Open full offer chat'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildMessageList(_selectedOfferMessages),
          ),
          _buildComposer(
            controller: _offerComposerCtrl,
            hintText: 'Write an offer message...',
            sending: _sendingOfferChat,
            onSend: _sendOfferMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<Map<String, dynamic>> messages) {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (messages.isEmpty) {
      return const Center(child: Text('No messages yet'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final message = messages[i];
        final senderId = (message['sender_id'] ?? message['created_by'])?.toString();
        final isMe = senderId != null && senderId == myId;
        final content = (message['content'] as String?) ?? '';

        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFF4EBDD) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE6DDCE)),
              ),
              child: Text(content),
            ),
          ),
        );
      },
    );
  }

  Widget _buildComposer({
    required TextEditingController controller,
    required String hintText,
    required bool sending,
    required VoidCallback onSend,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          border: const Border(
            top: BorderSide(color: Color(0xFFE6DDCE)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: hintText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFFBF8F2),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }
}
