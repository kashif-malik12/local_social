import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_language.dart';

class AppLocaleController extends StateNotifier<Locale> {
  AppLocaleController() : super(const Locale('fr'));

  AppLanguage get language => AppLanguage.fromCode(state.languageCode);

  Future<void> refreshFromProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      state = const Locale('fr');
      return;
    }

    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('app_language')
          .eq('id', user.id)
          .maybeSingle();
      final code = profile?['app_language']?.toString();
      state = Locale(AppLanguage.fromCode(code).code);
    } on PostgrestException {
      state = const Locale('fr');
    } catch (_) {
      state = const Locale('fr');
    }
  }

  void setLanguage(AppLanguage language) {
    state = Locale(language.code);
  }

  void reset() {
    state = const Locale('fr');
  }
}

final appLocaleProvider =
    StateNotifierProvider<AppLocaleController, Locale>((ref) {
  return AppLocaleController();
});
