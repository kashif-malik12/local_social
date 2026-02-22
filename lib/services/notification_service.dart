import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final SupabaseClient _db;
  NotificationService(this._db);

  String get _me => _db.auth.currentUser!.id;

  Future<List<Map<String, dynamic>>> fetchLatest({int limit = 50}) async {
    final rows = await _db
        .from('notifications')
        .select('*, actor:profiles!notifications_actor_id_fkey(full_name, avatar_url)')
        .eq('recipient_id', _me)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<int> unreadCount() async {
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('recipient_id', _me)
        .isFilter('read_at', null);

    return (rows as List).length;
  }

  Future<void> markAllRead() async {
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('recipient_id', _me)
        .isFilter('read_at', null);
  }

  Future<void> markRead(String notificationId) async {
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toIso8601String()})
        .eq('id', notificationId)
        .eq('recipient_id', _me);
  }

  /// Realtime: listen for new notifications
  RealtimeChannel subscribeToMyNotifications(void Function() onNew) {
    final channel = _db.channel('notifications-$_me');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: _me,
          ),
          callback: (payload) => onNew(),
        )
        .subscribe();

    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    await _db.removeChannel(channel);
  }
}