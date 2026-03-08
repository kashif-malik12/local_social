import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../widgets/global_bottom_nav.dart';
import '../../../widgets/chat_user_actions.dart';

import '../services/offer_chat_service.dart';

class OfferChatScreen extends StatefulWidget {
  final String conversationId;

  const OfferChatScreen({super.key, required this.conversationId});

  @override
  State<OfferChatScreen> createState() => _OfferChatScreenState();
}

class _OfferChatScreenState extends State<OfferChatScreen> {
  final _db = Supabase.instance.client;
  late final OfferChatService _service = OfferChatService(_db);
  final _textCtrl = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _postTitle = 'Offer chat';
  String? _postId;
  String _postType = '';
  String? _sellerId;
  String? _buyerId;
  String? _otherUserId;
  double? _currentOfferAmount;
  String _currentOfferStatus = 'none';
  String? _currentOfferBy;
  List<Map<String, dynamic>> _messages = [];
  RealtimeChannel? _msgChannel;
  RealtimeChannel? _convChannel;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    final msgChannel = _msgChannel;
    _msgChannel = null;
    if (msgChannel != null) {
      _db.removeChannel(msgChannel);
    }

    final convChannel = _convChannel;
    _convChannel = null;
    if (convChannel != null) {
      _db.removeChannel(convChannel);
    }

    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await _loadHeader();
      await _reloadMessages();
      await _service.markConversationRead(widget.conversationId);
      _subscribeRealtime();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadHeader() async {
    final me = _db.auth.currentUser?.id;
    if (me == null) throw Exception('Not logged in');

    final conversation = await _db
        .from('offer_conversations')
        .select(
          'id, post_id, buyer_id, seller_id, current_offer_amount, current_offer_status, current_offer_by',
        )
        .eq('id', widget.conversationId)
        .maybeSingle();

    if (conversation == null) {
      throw Exception('Offer chat is no longer available');
    }

    final postId = conversation['post_id'] as String?;
    final post = postId == null
        ? null
        : await _db
            .from('posts')
            .select('id, post_type, market_title, market_price, content')
            .eq('id', postId)
            .maybeSingle();

    if (post == null) {
      throw Exception('This listing is no longer available');
    }

    final rawTitle = (post['market_title'] as String?)?.trim();
    final content = (post['content'] as String?)?.trim() ?? '';
    if (!mounted) return;
    final otherUserId = me == conversation['buyer_id'] ? conversation['seller_id'] as String? : conversation['buyer_id'] as String?;
    setState(() {
      _postId = post['id'] as String?;
      _buyerId = conversation['buyer_id'] as String?;
      _sellerId = conversation['seller_id'] as String?;
      _otherUserId = otherUserId;
      _postType = (post['post_type'] as String?) ?? '';
      _postTitle = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : content;
      _currentOfferAmount =
          (conversation['current_offer_amount'] as num?)?.toDouble();
      _currentOfferStatus =
          (conversation['current_offer_status'] as String?)?.trim().isNotEmpty ==
                  true
              ? (conversation['current_offer_status'] as String)
              : 'none';
      _currentOfferBy = conversation['current_offer_by'] as String?;
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

  void _subscribeRealtime() {
    _msgChannel ??= _db.channel('offer-chat-${widget.conversationId}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'offer_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) async {
            await _loadHeader();
            await _reloadMessages();
            await _service.markConversationRead(widget.conversationId);
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'offer_messages',
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

    _convChannel ??= _db.channel('offer-conversation-${widget.conversationId}')
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'offer_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.conversationId,
          ),
          callback: (_) async {
            await _loadHeader();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'offer_conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.conversationId,
          ),
          callback: (_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('This offer chat is no longer available.')),
            );
            Navigator.of(context).maybePop();
          },
        )
        ..subscribe();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() => _busy = true);
    _textCtrl.clear();

    try {
      await _service.sendMessage(
        conversationId: widget.conversationId,
        content: text,
      );
      await _reloadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOfferFlow() async {
    if (_busy) return;

    final ctrl = TextEditingController(
      text: _currentOfferAmount == null
          ? ''
          : _currentOfferAmount!.toStringAsFixed(2),
    );
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_canCounterOffer ? 'Counter offer' : 'Make offer'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Amount',
            hintText: 'Enter amount',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = double.tryParse(ctrl.text.trim());
              Navigator.pop(context, parsed);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (amount == null || amount <= 0) return;

    setState(() => _busy = true);
    try {
      await _service.submitOffer(
        conversationId: widget.conversationId,
        amount: amount,
      );
      await _loadHeader();
      await _reloadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offer error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respondToOffer(String decision) async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      await _service.respondToOffer(
        conversationId: widget.conversationId,
        decision: decision,
      );
      await _loadHeader();
      await _reloadMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Offer response error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteConversation() async {
    if (_busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete offer chat?'),
        content: const Text('This removes the offer chat for both participants.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _service.deleteConversation(widget.conversationId);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete error: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _isBuyer => _db.auth.currentUser?.id == _buyerId;
  bool get _isSeller => _db.auth.currentUser?.id == _sellerId;
  bool get _hasPendingOffer =>
      _currentOfferStatus == 'pending' && _currentOfferAmount != null;
  bool get _canAcceptReject =>
      _hasPendingOffer && _currentOfferBy != _db.auth.currentUser?.id;
  bool get _canCounterOffer =>
      _currentOfferAmount != null && _currentOfferStatus != 'accepted';

  String _offerStatusLabel() {
    if (_currentOfferAmount == null) return 'No active offer yet';

    final who = _currentOfferBy == _buyerId
        ? (_isBuyer ? 'You' : 'Buyer')
        : (_isSeller ? 'You' : 'Seller');
    return 'Current offer: EUR ${_currentOfferAmount!.toStringAsFixed(2)} • ${_currentOfferStatus.toUpperCase()} • $who';
  }

  String _offerActionTitle() {
    if (!_hasPendingOffer) {
      return _canCounterOffer ? 'Offer updated' : 'Start an offer';
    }
    if (_canAcceptReject) {
      return 'Offer received';
    }
    return 'Waiting for response';
  }

  String? _listingRoute() {
    final postId = _postId;
    if (postId == null || postId.isEmpty) return null;
    if (_postType == 'market') return '/marketplace/product/$postId';
    if (_postType == 'service_offer' || _postType == 'service_request') {
      return '/gigs/service/$postId';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final myId = _db.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _postTitle.isEmpty ? 'Offer chat' : _postTitle,
          overflow: TextOverflow.ellipsis,
        ),
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
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
              ),
              icon: const Icon(Icons.more_vert),
            ),
          IconButton(
            tooltip: 'Home',
            onPressed: () => context.go('/feed'),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: 'Delete offer chat',
            onPressed: _busy ? null : _deleteConversation,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: const Color(0xFFE6DDCE)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_listingRoute() != null) ...[
                                        InkWell(
                                          onTap: () => context.push(_listingRoute()!),
                                          borderRadius: BorderRadius.circular(18),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF7F0E4),
                                              borderRadius: BorderRadius.circular(18),
                                              border: Border.all(color: const Color(0xFFE6DDCE)),
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 42,
                                                  height: 42,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF0F766E).withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(14),
                                                  ),
                                                  child: Icon(
                                                    _postType == 'market'
                                                        ? Icons.storefront_outlined
                                                        : Icons.work_outline,
                                                    color: const Color(0xFF0F766E),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        _postTitle,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w800,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      const Text(
                                                        'Open listing details',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Color(0xFF5B6B65),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const Icon(Icons.open_in_new, size: 18),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Text(
                                        _offerActionTitle(),
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _offerStatusLabel(),
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: _busy ? null : _submitOfferFlow,
                                            icon: const Icon(Icons.local_offer_outlined),
                                            label: Text(
                                              _canCounterOffer ? 'Counter offer' : 'Make offer',
                                            ),
                                          ),
                                          if (_canAcceptReject)
                                            FilledButton(
                                              onPressed:
                                                  _busy ? null : () => _respondToOffer('accepted'),
                                              child: const Text('Accept'),
                                            ),
                                          if (_canAcceptReject)
                                            OutlinedButton(
                                              onPressed:
                                                  _busy ? null : () => _respondToOffer('rejected'),
                                              child: const Text('Reject'),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, i) {
                                    final m = _messages[i];
                                    final senderId = m['sender_id'] as String?;
                                    final isMe = senderId != null && senderId == myId;
                                    final kind = (m['message_type'] as String?) ?? 'text';
                                    final amount = (m['offer_amount'] as num?)?.toDouble();
                                    final content = (m['content'] as String?) ?? '';

                                    final text = switch (kind) {
                                      'offer' => 'Made offer: EUR ${amount?.toStringAsFixed(2) ?? '--'}',
                                      'counter' => 'Counter offer: EUR ${amount?.toStringAsFixed(2) ?? '--'}',
                                      'accepted' => 'Offer accepted',
                                      'rejected' => 'Offer rejected',
                                      _ => content,
                                    };

                                    return Align(
                                      alignment:
                                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 620),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(vertical: 5),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 11,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isMe
                                                ? const Color(0xFFF4EBDD)
                                                : Colors.white,
                                            borderRadius: BorderRadius.circular(18),
                                            border: Border.all(
                                              color: const Color(0xFFE6DDCE),
                                            ),
                                          ),
                                          child: Text(
                                            text,
                                            style: const TextStyle(height: 1.35),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 920),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _textCtrl,
                                    textInputAction: TextInputAction.send,
                                    minLines: 1,
                                    maxLines: 4,
                                    onSubmitted: (_) => _send(),
                                    decoration: const InputDecoration(
                                      hintText: 'Message about this listing...',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: _busy ? null : _send,
                                  icon: const Icon(Icons.send),
                                  label: const Text('Send'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
