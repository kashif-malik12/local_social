import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnreadBadgeController {
  UnreadBadgeController(this._db);

  final SupabaseClient _db;

  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  StreamSubscription<List<Map<String, dynamic>>>? _sub1;
  StreamSubscription<List<Map<String, dynamic>>>? _sub2;

  Future<void> init() async {
    await refresh();

    // ✅ Simple + reliable: whenever messages change, refresh unread counter via RPC
    // (We can't perfectly filter realtime by "my conversations" without extra schema,
    // so we refresh by RPC on any insert/update seen by RLS.)
    _sub1 = _db
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((_) => refresh());

    // Also refresh when read_at changes (same stream covers updates too in most setups)
    // If your setup doesn't fire updates, uncomment below and use postgres_changes instead.
  }

  Future<void> refresh() async {
    try {
      final res = await _db.rpc('get_unread_total');
      unread.value = (res as num).toInt();
    } catch (_) {
      // ignore; keep last value
    }
  }

  void dispose() {
    _sub1?.cancel();
    _sub2?.cancel();
    unread.dispose();
  }
}