import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/food_categories.dart';
import '../../../core/market_categories.dart';
import '../../../core/service_categories.dart';
import '../../../widgets/global_app_bar.dart';
import '../../../widgets/global_bottom_nav.dart';

enum ManagedAdsMode { products, gigs, foods }

class ManagedAdsScreen extends StatefulWidget {
  final ManagedAdsMode mode;

  const ManagedAdsScreen({
    super.key,
    required this.mode,
  });

  @override
  State<ManagedAdsScreen> createState() => _ManagedAdsScreenState();
}

class _ManagedAdsScreenState extends State<ManagedAdsScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  bool _allowed = false;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _title {
    switch (widget.mode) {
      case ManagedAdsMode.products:
        return 'My products';
      case ManagedAdsMode.gigs:
        return 'My gigs';
      case ManagedAdsMode.foods:
        return 'My foods';
    }
  }

  List<String> get _postTypes {
    switch (widget.mode) {
      case ManagedAdsMode.products:
        return const ['market'];
      case ManagedAdsMode.gigs:
        return const ['service_offer', 'service_request'];
      case ManagedAdsMode.foods:
        return const ['food_ad', 'food'];
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) {
        throw Exception('Not logged in');
      }

      final profile = await _db
          .from('profiles')
          .select('is_restaurant')
          .eq('id', uid)
          .maybeSingle();

      final isRestaurant = profile?['is_restaurant'] == true;
      final allowed = widget.mode != ManagedAdsMode.foods || isRestaurant;

      if (!allowed) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _rows = [];
          _loading = false;
        });
        return;
      }

      final rows = await _db
          .from('posts')
          .select('id, content, image_url, created_at, post_type, market_title, market_price, market_category, market_intent, visibility')
          .eq('user_id', uid)
          .inFilter('post_type', _postTypes)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _allowed = true;
        _rows = (rows as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _categoryLabel(String raw) {
    switch (widget.mode) {
      case ManagedAdsMode.products:
        return marketCategoryLabel(raw);
      case ManagedAdsMode.gigs:
        return serviceCategoryLabel(raw);
      case ManagedAdsMode.foods:
        return foodCategoryLabel(raw);
    }
  }

  List<String> get _categoryOptions {
    switch (widget.mode) {
      case ManagedAdsMode.products:
        return marketMainCategories;
      case ManagedAdsMode.gigs:
        return serviceMainCategories;
      case ManagedAdsMode.foods:
        return foodMainCategories;
    }
  }

  Future<void> _deletePost(String postId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete ad?'),
        content: const Text('This will remove the ad from your listings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await _db.from('posts').delete().eq('id', postId).eq('user_id', _db.auth.currentUser!.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _editPost(Map<String, dynamic> row) async {
    final contentCtrl = TextEditingController(text: (row['content'] ?? '').toString());
    final titleCtrl = TextEditingController(text: (row['market_title'] ?? '').toString());
    final priceCtrl = TextEditingController(
      text: row['market_price'] == null ? '' : (row['market_price'] as num).toString(),
    );
    String category = ((row['market_category'] ?? '').toString().trim().isNotEmpty
            ? (row['market_category'] ?? '').toString()
            : _categoryOptions.first)
        .trim();
    String visibility = ((row['visibility'] ?? 'public').toString() == 'followers')
        ? 'followers'
        : 'public';
    String marketIntent = ((row['market_intent'] ?? 'selling').toString().trim().isNotEmpty
            ? (row['market_intent'] ?? 'selling').toString()
            : 'selling')
        .trim();
    String postType = ((row['post_type'] ?? '').toString().trim().isNotEmpty
            ? (row['post_type'] ?? '').toString()
            : _postTypes.first)
        .trim();
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit ${_title.substring(3, _title.length - (_title.endsWith('s') ? 1 : 0))}'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(labelText: 'Title'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: contentCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(labelText: 'Details'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Price'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: category,
                        items: _categoryOptions
                            .map((value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_categoryLabel(value)),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => category = value);
                        },
                        decoration: const InputDecoration(labelText: 'Category'),
                      ),
                      if (widget.mode == ManagedAdsMode.products) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: marketIntent,
                          items: const [
                            DropdownMenuItem(value: 'selling', child: Text('Selling')),
                            DropdownMenuItem(value: 'buying', child: Text('Buying')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => marketIntent = value);
                          },
                          decoration: const InputDecoration(labelText: 'Marketplace type'),
                        ),
                      ],
                      if (widget.mode == ManagedAdsMode.gigs) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: postType,
                          items: const [
                            DropdownMenuItem(value: 'service_offer', child: Text('Offering')),
                            DropdownMenuItem(value: 'service_request', child: Text('Requesting')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => postType = value);
                          },
                          decoration: const InputDecoration(labelText: 'Gig type'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: visibility,
                        items: const [
                          DropdownMenuItem(value: 'public', child: Text('Public')),
                          DropdownMenuItem(value: 'followers', child: Text('Local')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => visibility = value);
                        },
                        decoration: const InputDecoration(labelText: 'Visibility'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final price = double.tryParse(priceCtrl.text.trim());
                          if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Title and details are required')),
                            );
                            return;
                          }
                          if (price == null || price < 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Enter a valid price')),
                            );
                            return;
                          }

                          setDialogState(() => saving = true);
                          try {
                            await _db.from('posts').update({
                              'content': contentCtrl.text.trim(),
                              'market_title': titleCtrl.text.trim(),
                              'market_price': price,
                              'market_category': category,
                              'visibility': visibility,
                              if (widget.mode == ManagedAdsMode.products) 'market_intent': marketIntent,
                              if (widget.mode == ManagedAdsMode.gigs) 'post_type': postType,
                            }).eq('id', row['id']).eq('user_id', _db.auth.currentUser!.id);
                            if (!context.mounted) return;
                            Navigator.pop(dialogContext, true);
                          } catch (e) {
                            setDialogState(() => saving = false);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Update failed: $e')),
                            );
                          }
                        },
                  child: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );

    contentCtrl.dispose();
    titleCtrl.dispose();
    priceCtrl.dispose();

    if (saved == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlobalAppBar(
        title: _title,
        showBackIfPossible: true,
        homeRoute: '/feed',
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: !_allowed && !_loading
                ? const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('This page is only available to your own eligible profile.'),
                    ),
                  )
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _rows.isEmpty
                            ? Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text('No ${_title.toLowerCase()} yet.'),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final row = _rows[index];
                                  final title = ((row['market_title'] ?? '').toString().trim().isNotEmpty
                                          ? row['market_title']
                                          : row['content'])
                                      .toString();
                                  final category = _categoryLabel((row['market_category'] ?? '').toString());
                                  final price = (row['market_price'] as num?)?.toDouble();
                                  final createdAt = (row['created_at'] ?? '').toString();
                                  final visibility = (row['visibility'] ?? 'public').toString() == 'followers'
                                      ? 'Local'
                                      : 'Public';
                                  final imageUrl = (row['image_url'] ?? '').toString();
                                  final type = (row['post_type'] ?? '').toString();

                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(14),
                                            child: Container(
                                              width: 110,
                                              height: 110,
                                              color: const Color(0xFFF4EBDD),
                                              child: imageUrl.isEmpty
                                                  ? const Icon(Icons.image_outlined)
                                                  : Image.network(
                                                      imageUrl,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (_, _, _) =>
                                                          const Icon(Icons.broken_image_outlined),
                                                    ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  title,
                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                ),
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    _Chip(label: category),
                                                    if (price != null)
                                                      _Chip(label: 'EUR ${price.toStringAsFixed(2)}'),
                                                    _Chip(label: visibility),
                                                    if (widget.mode == ManagedAdsMode.products)
                                                      _Chip(
                                                        label: ((row['market_intent'] ?? 'selling')
                                                                    .toString() ==
                                                                'buying')
                                                            ? 'Buying'
                                                            : 'Selling',
                                                      ),
                                                    if (widget.mode == ManagedAdsMode.gigs)
                                                      _Chip(
                                                        label: type == 'service_request'
                                                            ? 'Requesting'
                                                            : 'Offering',
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  (row['content'] ?? '').toString(),
                                                  maxLines: 3,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  'Created: $createdAt',
                                                  style: Theme.of(context).textTheme.bodySmall,
                                                ),
                                                const SizedBox(height: 12),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: [
                                                    OutlinedButton.icon(
                                                      onPressed: () => _editPost(row),
                                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                                      label: const Text('Edit'),
                                                    ),
                                                    OutlinedButton.icon(
                                                      onPressed: () => _deletePost((row['id'] ?? '').toString()),
                                                      icon: const Icon(Icons.delete_outline, size: 18),
                                                      label: const Text('Delete'),
                                                    ),
                                                    OutlinedButton.icon(
                                                      onPressed: () {
                                                        switch (widget.mode) {
                                                          case ManagedAdsMode.products:
                                                            context.push('/marketplace/product/${row['id']}');
                                                            break;
                                                          case ManagedAdsMode.gigs:
                                                            context.push('/gigs/service/${row['id']}');
                                                            break;
                                                          case ManagedAdsMode.foods:
                                                            context.push('/foods/${row['id']}');
                                                            break;
                                                        }
                                                      },
                                                      icon: const Icon(Icons.open_in_new, size: 18),
                                                      label: const Text('Open'),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EBDD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
