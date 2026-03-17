import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/food_categories.dart';
import '../../../core/market_categories.dart';
import '../../../core/service_categories.dart';
import '../../../services/feed_filter_service.dart';

class FeedFilterSetupScreen extends StatefulWidget {
  const FeedFilterSetupScreen({super.key});

  @override
  State<FeedFilterSetupScreen> createState() => _FeedFilterSetupScreenState();
}

class _FeedFilterSetupScreenState extends State<FeedFilterSetupScreen> {
  final _service = FeedFilterService(Supabase.instance.client);

  bool _loading = true;
  bool _saving = false;

  bool _generalPostsEnabled = true;
  String _generalPostsScope = 'all';
  bool _marketplaceEnabled = true;
  final Set<String> _selectedMarketplaceIntents = {'buying', 'selling'};
  final Set<String> _selectedMarketplaceCategories = {};
  bool _gigsEnabled = true;
  final Set<String> _selectedGigTypes = {'service_offer', 'service_request'};
  final Set<String> _selectedGigCategories = {};
  bool _lostFoundEnabled = true;
  String _lostFoundScope = 'all';
  bool _foodAdsEnabled = true;
  final Set<String> _selectedFoodCategories = {};
  bool _organizationsEnabled = false;
  final Set<String> _selectedOrganizationKinds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _service.load();
    final data = saved ?? FeedFilterService.defaultFilters();
    if (!mounted) return;
    _applyFilterData(data);
    setState(() => _loading = false);
  }

  void _applyFilterData(Map<String, dynamic> data) {
    _generalPostsEnabled = data['general_enabled'] != false;
    _generalPostsScope = (data['general_scope'] as String?) ?? 'all';
    _marketplaceEnabled = data['market_enabled'] != false;
    _selectedMarketplaceIntents
      ..clear()
      ..addAll(((data['market_intents'] as List?) ?? const []).map((e) => e.toString()));
    _selectedMarketplaceCategories
      ..clear()
      ..addAll(((data['market_categories'] as List?) ?? const []).map((e) => e.toString()));
    _gigsEnabled = data['gigs_enabled'] != false;
    _selectedGigTypes
      ..clear()
      ..addAll(((data['gig_types'] as List?) ?? const []).map((e) => e.toString()));
    _selectedGigCategories
      ..clear()
      ..addAll(((data['gig_categories'] as List?) ?? const []).map((e) => e.toString()));
    _lostFoundEnabled = data['lost_found_enabled'] != false;
    _lostFoundScope = (data['lost_found_scope'] as String?) ?? 'all';
    _foodAdsEnabled = data['food_enabled'] != false;
    _selectedFoodCategories
      ..clear()
      ..addAll(((data['food_categories'] as List?) ?? const []).map((e) => e.toString()));
    _organizationsEnabled = data['org_enabled'] == true;
    _selectedOrganizationKinds
      ..clear()
      ..addAll(((data['org_kinds'] as List?) ?? const []).map((e) => e.toString()));
  }

  Map<String, dynamic> _currentFilters() {
    return {
      'general_enabled': _generalPostsEnabled,
      'general_scope': _generalPostsScope,
      'market_enabled': _marketplaceEnabled,
      'market_intents': _selectedMarketplaceIntents.toList(),
      'market_categories': _selectedMarketplaceCategories.toList(),
      'gigs_enabled': _gigsEnabled,
      'gig_types': _selectedGigTypes.toList(),
      'gig_categories': _selectedGigCategories.toList(),
      'lost_found_enabled': _lostFoundEnabled,
      'lost_found_scope': _lostFoundScope,
      'food_enabled': _foodAdsEnabled,
      'food_categories': _selectedFoodCategories.toList(),
      'org_enabled': _organizationsEnabled,
      'org_kinds': _selectedOrganizationKinds.toList(),
    };
  }

  bool _hasInvalidRequiredSelections() {
    return (_marketplaceEnabled && _selectedMarketplaceCategories.isEmpty) ||
        (_gigsEnabled && _selectedGigCategories.isEmpty) ||
        (_foodAdsEnabled && _selectedFoodCategories.isEmpty) ||
        (_organizationsEnabled && _selectedOrganizationKinds.isEmpty);
  }

  Future<void> _saveAndContinue() async {
    if (_saving || _hasInvalidRequiredSelections()) return;
    setState(() => _saving = true);
    await _service.save(_currentFilters());
    if (!mounted) return;
    context.go('/feed');
  }

  void _reset() {
    setState(() {
      _applyFilterData(FeedFilterService.defaultFilters());
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Choose your feed',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Select what you want to see in your feed before continuing.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _reset,
                          child: const Text('Reset'),
                        ),
                      ),
                      _buildFilterSectionCard(
                        title: 'General posts',
                        subtitle: 'Normal feed posts only.',
                        enabled: _generalPostsEnabled,
                        onEnabledChanged: (value) {
                          setState(() => _generalPostsEnabled = value);
                        },
                        child: _buildScopeChips(
                          selected: _generalPostsScope,
                          onSelected: (value) {
                            setState(() => _generalPostsScope = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Marketplace posts',
                        subtitle: 'Buying, selling, and product categories.',
                        enabled: _marketplaceEnabled,
                        onEnabledChanged: (value) {
                          setState(() => _marketplaceEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: 'Marketplace type',
                              options: const [('buying', 'Buying'), ('selling', 'Selling')],
                              selected: _selectedMarketplaceIntents,
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Marketplace categories',
                              options: marketMainCategories
                                  .map((c) => (c, marketCategoryLabel(c)))
                                  .toList(),
                              selected: _selectedMarketplaceCategories,
                            ),
                            if (_selectedMarketplaceCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one category.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Gig posts',
                        subtitle: 'Service offers, requests, and service categories.',
                        enabled: _gigsEnabled,
                        onEnabledChanged: (value) {
                          setState(() => _gigsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: 'Gig type',
                              options: const [
                                ('service_offer', 'Offering'),
                                ('service_request', 'Requesting'),
                              ],
                              selected: _selectedGigTypes,
                            ),
                            const SizedBox(height: 12),
                            _buildMultiSelectSection(
                              title: 'Service categories',
                              options: serviceMainCategories
                                  .map((c) => (c, serviceCategoryLabel(c)))
                                  .toList(),
                              selected: _selectedGigCategories,
                            ),
                            if (_selectedGigCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one category.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Lost & found',
                        subtitle: 'Show or hide lost-and-found posts.',
                        enabled: _lostFoundEnabled,
                        onEnabledChanged: (value) {
                          setState(() => _lostFoundEnabled = value);
                        },
                        child: _buildScopeChips(
                          selected: _lostFoundScope,
                          onSelected: (value) {
                            setState(() => _lostFoundScope = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Food ads',
                        subtitle: 'Food posts with separate food categories.',
                        enabled: _foodAdsEnabled,
                        onEnabledChanged: (value) {
                          setState(() => _foodAdsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: 'Food categories',
                              options: foodMainCategories
                                  .map((c) => (c, foodCategoryLabel(c)))
                                  .toList(),
                              selected: _selectedFoodCategories,
                            ),
                            if (_selectedFoodCategories.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one category.'),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFilterSectionCard(
                        title: 'Organizations',
                        subtitle: 'Show organization posts by subtype.',
                        enabled: _organizationsEnabled,
                        onEnabledChanged: (value) {
                          setState(() => _organizationsEnabled = value);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildMultiSelectSection(
                              title: 'Organization types',
                              options: const [
                                ('government', 'Government'),
                                ('nonprofit', 'Non-profit'),
                                ('news_agency', 'News agency'),
                              ],
                              selected: _selectedOrganizationKinds,
                            ),
                            if (_selectedOrganizationKinds.isEmpty) ...[
                              const SizedBox(height: 8),
                              _buildFilterWarning('Select at least one type.'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _hasInvalidRequiredSelections() ? null : _saveAndContinue,
                  child: Text(_saving ? 'Saving...' : 'Continue to feed'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterWarning(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5C26B)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9A6700),
        ),
      ),
    );
  }

  Widget _buildFilterSectionCard({
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onEnabledChanged,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCF7),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6DDCE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: enabled,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }

  Widget _buildScopeChips({
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    const options = [
      ('all', 'Public + Following'),
      ('public', 'Public'),
      ('following', 'Following'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((entry) {
        final isSelected = selected == entry.$1;
        return ChoiceChip(
          selected: isSelected,
          label: Text(entry.$2),
          onSelected: (_) => onSelected(entry.$1),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  Widget _buildMultiSelectSection({
    required String title,
    required List<(String, String)> options,
    required Set<String> selected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((entry) {
            final value = entry.$1;
            final isSelected = selected.contains(value);
            return FilterChip(
              selected: isSelected,
              label: Text(entry.$2),
              showCheckmark: false,
              onSelected: (_) {
                setState(() {
                  if (isSelected) {
                    selected.remove(value);
                  } else {
                    selected.add(value);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
