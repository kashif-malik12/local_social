import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/portfolio_item.dart';

class PortfolioService {
  final SupabaseClient _db;
  PortfolioService(this._db);

  Future<List<PortfolioItem>> fetchPortfolio(String profileId) async {
    final res = await _db
        .from('profile_portfolio')
        .select()
        .eq('profile_id', profileId)
        .order('created_at', ascending: false);

    return (res as List)
        .map((e) => PortfolioItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> addPortfolioImage({
    required String profileId,
    required Uint8List bytes,
    required String fileExt, // jpg/png
  }) async {
    final safeExt = (fileExt.toLowerCase() == 'png') ? 'png' : 'jpg';
    final path =
        'portfolio/$profileId/${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    await _db.storage.from('portfolio-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: safeExt == 'png' ? 'image/png' : 'image/jpeg',
          ),
        );

    final publicUrl = _db.storage.from('portfolio-images').getPublicUrl(path);

    await _db.from('profile_portfolio').insert({
      'profile_id': profileId,
      'image_url': publicUrl,
    });
  }

  Future<void> deletePortfolioItem({required String itemId}) async {
    await _db.from('profile_portfolio').delete().eq('id', itemId);
  }
}