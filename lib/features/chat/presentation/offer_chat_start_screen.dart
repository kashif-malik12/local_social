import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/offer_chat_service.dart';

class OfferChatStartScreen extends StatefulWidget {
  final String postId;
  final String otherUserId;

  const OfferChatStartScreen({
    super.key,
    required this.postId,
    required this.otherUserId,
  });

  @override
  State<OfferChatStartScreen> createState() => _OfferChatStartScreenState();
}

class _OfferChatStartScreenState extends State<OfferChatStartScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final service = OfferChatService(Supabase.instance.client);
      final convId = await service.getOrCreateConversation(
        postId: widget.postId,
        otherUserId: widget.otherUserId,
      );
      if (!mounted) return;
      context.go('/offer-chat/$convId');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Offer chat'),
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
        ],
      ),
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
