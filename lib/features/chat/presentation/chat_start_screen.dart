import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../widgets/global_bottom_nav.dart';
import '../services/chat_service.dart';

class ChatStartScreen extends StatefulWidget {
  final String otherUserId;
  const ChatStartScreen({super.key, required this.otherUserId});

  @override
  State<ChatStartScreen> createState() => _ChatStartScreenState();
}

class _ChatStartScreenState extends State<ChatStartScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final service = ChatService(Supabase.instance.client);
      final convId = await service.getOrCreateConversation(widget.otherUserId);
      if (!mounted) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.replace('/chat/$convId');
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
      ),
    );
  }
}
