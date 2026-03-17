import 'package:flutter/material.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../services/app_settings_service.dart';
import '../../../widgets/global_app_bar.dart';
import '../../../widgets/global_bottom_nav.dart';

class _SettingItem {
  const _SettingItem({
    required this.keyName,
    required this.title,
    required this.subtitle,
  });

  final String keyName;
  final String title;
  final String subtitle;
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late AppSettings _settings;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _settings = AppSettingsService.loadCurrentSettings();
  }

  Future<void> _updateSetting(String key, bool enabled) async {
    final previous = _settings;
    setState(() {
      _settings = _settings.copyWithValue(key, enabled);
      _saving = true;
    });

    try {
      final updated = await AppSettingsService.setBool(key, enabled);
      if (!mounted) return;
      setState(() => _settings = updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _settings = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.tr('failed_to_save_setting', args: {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildSettingsCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required List<_SettingItem> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            for (final item in items)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _settings.enabled(item.keyName),
                onChanged: _saving ? null : (value) => _updateSetting(item.keyName, value),
                title: Text(item.title),
                subtitle: Text(item.subtitle),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: GlobalAppBar(
        title: l10n.tr('profile_settings'),
        showBackIfPossible: true,
        homeRoute: '/profile',
      ),
      bottomNavigationBar: const GlobalBottomNav(),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSettingsCard(
                context: context,
                title: l10n.tr('playback'),
                subtitle: l10n.tr('playback_subtitle'),
                items: [
                  _SettingItem(
                    keyName: AppSettingsService.videoAutoplayKey,
                    title: l10n.tr('video_auto_play'),
                    subtitle: l10n.tr('video_auto_play_subtitle'),
                  ),
                ],
              ),
              _buildSettingsCard(
                context: context,
                title: l10n.tr('in_app_notifications'),
                subtitle: l10n.tr('in_app_notifications_subtitle'),
                items: [
                  _SettingItem(
                    keyName: AppSettingsService.inAppChatMessagesKey,
                    title: l10n.tr('chat_messages'),
                    subtitle: l10n.tr('chat_messages_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppOfferMessagesKey,
                    title: l10n.tr('offer_messages'),
                    subtitle: l10n.tr('offer_messages_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppOfferUpdatesKey,
                    title: l10n.tr('offer_updates'),
                    subtitle: l10n.tr('offer_updates_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppCommentsKey,
                    title: l10n.tr('comments_on_my_posts'),
                    subtitle: l10n.tr('comments_on_my_posts_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppRepliesKey,
                    title: l10n.tr('replies_to_my_comments'),
                    subtitle: l10n.tr('replies_to_my_comments_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppMentionsKey,
                    title: l10n.tr('mentions'),
                    subtitle: l10n.tr('mentions_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppFollowRequestsKey,
                    title: l10n.tr('follow_requests'),
                    subtitle: l10n.tr('follow_requests_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppNewFollowersKey,
                    title: l10n.tr('new_followers'),
                    subtitle: l10n.tr('new_followers_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.inAppAdminUpdatesKey,
                    title: l10n.tr('admin_and_safety_updates'),
                    subtitle: l10n.tr('admin_and_safety_updates_subtitle'),
                  ),
                ],
              ),
              _buildSettingsCard(
                context: context,
                title: l10n.tr('push_notifications'),
                subtitle: l10n.tr('push_notifications_subtitle'),
                items: [
                  _SettingItem(
                    keyName: AppSettingsService.pushChatMessagesKey,
                    title: l10n.tr('push_chat_messages'),
                    subtitle: l10n.tr('push_chat_messages_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushOfferMessagesKey,
                    title: l10n.tr('push_offer_messages'),
                    subtitle: l10n.tr('push_offer_messages_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushOfferUpdatesKey,
                    title: l10n.tr('push_offer_updates'),
                    subtitle: l10n.tr('push_offer_updates_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushCommentsKey,
                    title: l10n.tr('push_comments'),
                    subtitle: l10n.tr('push_comments_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushRepliesKey,
                    title: l10n.tr('push_replies'),
                    subtitle: l10n.tr('push_replies_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushMentionsKey,
                    title: l10n.tr('push_mentions'),
                    subtitle: l10n.tr('push_mentions_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushFollowRequestsKey,
                    title: l10n.tr('push_follow_requests'),
                    subtitle: l10n.tr('push_follow_requests_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushNewFollowersKey,
                    title: l10n.tr('push_new_followers'),
                    subtitle: l10n.tr('push_new_followers_subtitle'),
                  ),
                  _SettingItem(
                    keyName: AppSettingsService.pushAdminUpdatesKey,
                    title: l10n.tr('push_admin_updates'),
                    subtitle: l10n.tr('push_admin_updates_subtitle'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
