import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final adminAccessProvider = FutureProvider<bool>((ref) async {
  final client = Supabase.instance.client;
  final uid = client.auth.currentUser?.id;
  if (uid == null) return false;

  final row = await client.from('profiles').select('is_admin').eq('id', uid).maybeSingle();
  return row?['is_admin'] == true;
});
