import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/chat_service.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _service = ChatService(Supabase.instance.client);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rows.isEmpty
                  ? const Center(child: Text('No conversations yet'))
                  : ListView.separated(
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
                    ),
    );
  }
}