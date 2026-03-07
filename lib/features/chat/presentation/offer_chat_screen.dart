import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  String _postType = '';
  String _priceLabel = '';
  String? _sellerId;
  String? _buyerId;
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
    final price = (post['market_price'] as num?)?.toDouble();

    if (!mounted) return;
    setState(() {
      _buyerId = conversation['buyer_id'] as String?;
      _sellerId = conversation['seller_id'] as String?;
      _postType = (post['post_type'] as String?) ?? '';
      _postTitle = (rawTitle != null && rawTitle.isNotEmpty) ? rawTitle : content;
      _priceLabel = price == null ? '' : 'EUR ${price.toStringAsFixed(2)}';
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
    if (_msgChannel == null) {
      _msgChannel = _db.channel('offer-chat-${widget.conversationId}')
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
    }

    if (_convChannel == null) {
      _convChannel = _db.channel('offer-conversation-${widget.conversationId}')
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

  String _postTypeLabel() {
    switch (_postType) {
      case 'market':
        return 'Product';
      case 'service_offer':
        return 'Service offer';
      case 'service_request':
        return 'Service request';
      default:
        return 'Listing';
    }
  }

  String _offerStatusLabel() {
    if (_currentOfferAmount == null) return 'No active offer yet';

    final who = _currentOfferBy == _buyerId
        ? (_isBuyer ? 'You' : 'Buyer')
        : (_isSeller ? 'You' : 'Seller');
    return 'Current offer: EUR ${_currentOfferAmount!.toStringAsFixed(2)} - ${_currentOfferStatus.toUpperCase()} - $who';
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: Border(
                          bottom: BorderSide(color: Theme.of(context).dividerColor),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [
                              _postTypeLabel(),
                              if (_priceLabel.isNotEmpty) _priceLabel,
                            ].join(' - '),
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _offerActionTitle(),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _offerStatusLabel(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _submitOfferFlow,
                                icon: const Icon(Icons.local_offer_outlined),
                                label: Text(
                                  _canCounterOffer ? 'Counter offer' : 'Make offer',
                                ),
                              ),
                              if (_canAcceptReject)
                                ElevatedButton(
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
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Colors.green.withOpacity(0.15)
                                    : Colors.grey.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(text),
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
                                  hintText: 'Message about this listing...',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: _busy ? null : _send,
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
