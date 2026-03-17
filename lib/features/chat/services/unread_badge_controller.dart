import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnreadBadgeController {
  UnreadBadgeController(this._db);

  final SupabaseClient _db;

  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  RealtimeChannel? _channel;
  Timer? _fallbackRefreshTimer;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) {
      await refresh();
      return;
    }

    _initialized = true;
    await refresh();

    _fallbackRefreshTimer ??=
        Timer.periodic(const Duration(seconds: 45), (_) => refresh());

    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    if (_channel != null) return;

    final channel = _db.channel('unread-badge');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (_) => refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'offer_messages',
          callback: (_) => refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (_) => refresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'offer_messages',
          callback: (_) => refresh(),
        )
        .subscribe((status, [error]) {
          if (error != null) {
            debugPrint('Unread badge realtime error: $error');
          }
        });

    _channel = channel;
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        _db.rpc('get_unread_total'),
        _db.rpc('get_offer_chat_list'),
      ]);

      final dmUnread = (results[0] as num).toInt();
      final offerRows = (results[1] as List).cast<Map<String, dynamic>>();
      final offerUnread = offerRows.fold<int>(
        0,
        (sum, row) => sum + (((row['unread_count'] as num?)?.toInt()) ?? 0),
      );

      unread.value = dmUnread + offerUnread;
    } catch (_) {
      // Keep the last known value if refresh fails.
    }
  }

  void dispose() {
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      _db.removeChannel(ch);
    }
    _fallbackRefreshTimer?.cancel();
    _fallbackRefreshTimer = null;
    _initialized = false;
    unread.value = 0;
  }
}
