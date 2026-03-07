import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/service_categories.dart';
import '../models/post_model.dart';
import '../widgets/global_app_bar.dart';

class GigDetailScreen extends StatefulWidget {
  final String postId;
  const GigDetailScreen({super.key, required this.postId});

  @override
  State<GigDetailScreen> createState() => _GigDetailScreenState();
}

class _GigDetailScreenState extends State<GigDetailScreen> {
  bool _loading = true;
  String? _error;
  Post? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _typeLabel(String? postType) {
    if (postType == 'service_offer') return 'Offering service';
    if (postType == 'service_request') return 'Requesting service';
    return '';
  }

  double? _priceFromContent(String raw) {
    final patterns = [
      RegExp(r'(?:price|budget|rate)\s*:\s*(\d+(?:[.,]\d{1,2})?)',
          caseSensitive: false),
      RegExp(r'(?:price|budget|rate)\s*:\s*(?:eur|euro|€|\$)\s*(\d+(?:[.,]\d{1,2})?)',
          caseSensitive: false),
      RegExp(r'(?:eur|euro|€)\s*(\d+(?:[.,]\d{1,2})?)', caseSensitive: false),
      RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*eur', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(raw);
      if (match != null) {
        final value = (match.group(match.groupCount) ?? '').replaceAll(',', '.');
        final parsed = double.tryParse(value);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, avatar_url, city, zipcode)')
          .eq('id', widget.postId)
          .inFilter('post_type', ['service_offer', 'service_request'])
          .maybeSingle();

      if (row == null) {
        throw Exception('Service not found');
      }

      if (!mounted) return;
      setState(() => _post = Post.fromMap(row));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final canSendOffer = p != null && myId != null && p.userId != myId;
    final effectivePrice =
        p == null ? null : (p.marketPrice ?? _priceFromContent(p.content));

    return Scaffold(
      appBar: const GlobalAppBar(
        title: 'Service details',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : p == null
                  ? const Center(child: Text('Service not found'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        AspectRatio(
                          aspectRatio: 1.2,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              color: Colors.grey.shade200,
                              child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                                  ? Image.network(
                                      p.imageUrl!,
                                      fit: BoxFit.cover,
                                    )
                                  : const Icon(
                                      Icons.miscellaneous_services_outlined,
                                      size: 64,
                                      color: Colors.black45,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          (p.marketTitle ?? '').trim().isNotEmpty
                              ? p.marketTitle!.trim()
                              : p.content,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          effectivePrice != null
                              ? 'EUR ${effectivePrice.toStringAsFixed(2)}'
                              : (p.postType == 'service_request'
                                  ? 'Budget open'
                                  : 'Rate on request'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (((p.authorCity ?? '').trim().isNotEmpty) ||
                            ((p.authorZipcode ?? '').trim().isNotEmpty))
                          Text(
                            'Location: ${((p.authorCity ?? '').trim().isNotEmpty ? p.authorCity!.trim() : p.authorZipcode!.trim())}',
                          ),
                        if (((p.authorCity ?? '').trim().isNotEmpty) ||
                            ((p.authorZipcode ?? '').trim().isNotEmpty))
                          const SizedBox(height: 8),
                        if ((p.marketCategory ?? '').isNotEmpty)
                          Text(
                            'Category: ${serviceCategoryLabel(p.marketCategory!)}',
                          ),
                        if ((p.postType ?? '').isNotEmpty)
                          Text('Type: ${_typeLabel(p.postType)}'),
                        const SizedBox(height: 16),
                        const Text(
                          'Description',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(p.content),
                        if (canSendOffer) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => context.push(
                                '/offer-chat/post/${p.id}/user/${p.userId}',
                              ),
                              icon: const Icon(Icons.local_offer_outlined),
                              label: const Text('Send Offer'),
                            ),
                          ),
                        ],
                      ],
                    ),
    );
  }
}
