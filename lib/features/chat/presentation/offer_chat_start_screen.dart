import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../widgets/global_bottom_nav.dart';

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
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.replace('/offer-chat/$convId');
      });
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
      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _error == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Preparing your offer chat...',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    )
                  : Text(_error!, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
