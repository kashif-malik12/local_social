import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final notificationUnreadProvider =
    StateNotifierProvider<NotificationUnreadNotifier, int>(
  (ref) => NotificationUnreadNotifier(ref),
);

class NotificationUnreadNotifier extends StateNotifier<int> {
  NotificationUnreadNotifier(this.ref) : super(0);

  final Ref ref;
  final _db = Supabase.instance.client;

  RealtimeChannel? _channel;
  Timer? _debounce;

  String? get _uid => _db.auth.currentUser?.id;

  /// Call once after login / when HomeScreen starts
  Future<void> init() async {
    // if already initialized, don't double-subscribe
    if (_channel != null) return;

    await refresh();
    _subscribeRealtime();
  }

  /// Call on logout / when leaving app root
  Future<void> disposeRealtime() async {
    _debounce?.cancel();
    _debounce = null;

    final ch = _channel;
    _channel = null;
    if (ch != null) {
      await _db.removeChannel(ch);
    }
  }

  Future<void> refresh() async {
    final uid = _uid;
    if (uid == null) {
      state = 0;
      return;
    }

    // Efficient way: just select ids and count locally.
    // If your notifications table grows a lot, we can switch to a RPC count function.
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('recipient_id', uid)
        .isFilter('read_at', null);

    state = (rows as List).length;
  }

  /// Optimistic helpers (use from UI when marking read)
  void decrement() {
    if (state > 0) state = state - 1;
  }

  void clear() {
    state = 0;
  }

  void _subscribeRealtime() {
    final uid = _uid;
    if (uid == null) return;

    // Channel name must be unique per user to avoid collisions
    final channel = _db.channel('notifications-unread-$uid');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: uid,
      ),
      callback: (payload) {
        // When new notification arrives, bump count
        // But to be safe (e.g. read_at set immediately or race), debounce a refresh.
        state = state + 1;

        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () {
          refresh();
        });
      },
    ).subscribe();

    _channel = channel;
  }
}