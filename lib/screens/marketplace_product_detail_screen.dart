import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/market_categories.dart';
import '../models/post_model.dart';
import '../widgets/global_app_bar.dart';

class MarketplaceProductDetailScreen extends StatefulWidget {
  final String postId;
  const MarketplaceProductDetailScreen({super.key, required this.postId});

  @override
  State<MarketplaceProductDetailScreen> createState() =>
      _MarketplaceProductDetailScreenState();
}

class _MarketplaceProductDetailScreenState
    extends State<MarketplaceProductDetailScreen> {
  bool _loading = true;
  String? _error;
  Post? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _intentLabel(String? intent) {
    switch (intent) {
      case 'buying':
        return 'Buying';
      case 'selling':
        return 'Selling';
      default:
        return (intent ?? '').trim();
    }
  }

  double? _priceFromContent(String raw) {
    final patterns = [
      RegExp(r'price\s*:\s*(\d+(?:[.,]\d{1,2})?)', caseSensitive: false),
      RegExp(r'price\s*:\s*(?:eur|euro|€|\$)\s*(\d+(?:[.,]\d{1,2})?)',
          caseSensitive: false),
      RegExp(r'(?:eur|euro|€)\s*(\d+(?:[.,]\d{1,2})?)', caseSensitive: false),
      RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*eur', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(raw);
      if (match != null) {
        final value = (match.group(1) ?? '').replaceAll(',', '.');
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
          .eq('post_type', 'market')
          .maybeSingle();

      if (row == null) {
        throw Exception('Product not found');
      }

      if (!mounted) return;
      setState(() {
        _post = Post.fromMap(row);
      });
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
        title: 'Product details',
        showBackIfPossible: true,
        homeRoute: '/feed',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : p == null
                  ? const Center(child: Text('Product not found'))
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
                                      Icons.image_outlined,
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
                              : (p.marketIntent == 'buying'
                                  ? 'Looking to buy'
                                  : 'Price on request'),
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
                            'Category: ${marketCategoryLabel(p.marketCategory!)}',
                          ),
                        if ((p.marketIntent ?? '').isNotEmpty)
                          Text('Type: ${_intentLabel(p.marketIntent)}'),
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
