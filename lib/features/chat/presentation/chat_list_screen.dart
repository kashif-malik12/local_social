import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../widgets/global_app_bar.dart';
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

  bool _loading = true;
  bool _offerLoading = true;
  String? _error;
  String? _offerError;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _offerRows = [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.getChatList();
      setState(() => _rows = rows);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadOffers() async {
    setState(() {
      _offerLoading = true;
      _offerError = null;
    });
    try {
      final rows = await _offerService.getChatList();
      setState(() => _offerRows = rows);
    } catch (e) {
      setState(() => _offerError = e.toString());
    } finally {
      setState(() => _offerLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _load(),
      _loadOffers(),
    ]);
  }

  @override
  void initState() {
    super.initState();
    _refreshAll();
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
                  _buildNormalChats(),
                  _buildOfferChats(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalChats() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('No conversations yet'));
    }

    return ListView.separated(
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _rows[i];
        final convId = r['conversation_id'] as String;
        final name = (r['other_full_name'] as String?) ?? 'Unknown';
        final last = (r['last_message'] as String?) ?? '';
        final unread = (r['unread_count'] as num?)?.toInt() ?? 0;

        return ListTile(
          leading: CircleAvatar(
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?'),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: unread > 0
              ? CircleAvatar(
                  radius: 12,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              : null,
          onTap: () => context.push('/chat/$convId'),
        );
      },
    );
  }

  Widget _buildOfferChats() {
    if (_offerLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_offerError != null) {
      return Center(child: Text(_offerError!));
    }
    if (_offerRows.isEmpty) {
      return const Center(child: Text('No offer chats yet'));
    }

    return ListView.separated(
      itemCount: _offerRows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final r = _offerRows[i];
        final convId = (r['conversation_id'] ?? '').toString();
        final postTitle = (r['post_title'] as String?) ?? 'Listing';
        final name = (r['other_full_name'] as String?) ?? 'Unknown';
        final last = (r['last_message'] as String?) ?? '';
        final unread = (r['unread_count'] as num?)?.toInt() ?? 0;
        final status = (r['current_offer_status'] as String?) ?? '';
        final amount = (r['current_offer_amount'] as num?)?.toDouble();

        final meta = <String>[
          name,
          if (status.isNotEmpty && status != 'none') status.toUpperCase(),
          if (amount != null) 'EUR ${amount.toStringAsFixed(2)}',
        ].join(' • ');

        return ListTile(
          leading: const CircleAvatar(
            child: Icon(Icons.local_offer_outlined),
          ),
          title: Text(postTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (meta.isNotEmpty)
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (last.isNotEmpty)
                Text(last, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: unread > 0
              ? CircleAvatar(
                  radius: 12,
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(fontSize: 12),
                  ),
                )
              : null,
          onTap: convId.isEmpty ? null : () => context.push('/offer-chat/$convId'),
        );
      },
    );
  }
}
