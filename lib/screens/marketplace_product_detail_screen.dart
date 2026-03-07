import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/market_categories.dart';
import '../models/post_model.dart';

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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(full_name, avatar_url)')
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

    return Scaffold(
      appBar: AppBar(title: const Text('Product details')),
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
                          p.marketPrice != null
                              ? '€${p.marketPrice!.toStringAsFixed(2)}'
                              : (p.marketIntent == 'buying'
                                  ? 'Looking to buy'
                                  : 'Price on request'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('Seller: ${p.authorName ?? 'Unknown'}'),
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
                      ],
                    ),
    );
  }
}