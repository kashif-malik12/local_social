import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

LocalStorage createReleaseAuthStorage(String persistSessionKey) =>
    _PrefsLocalStorage(persistSessionKey: persistSessionKey);

GotrueAsyncStorage createReleasePkceStorage() =>
    const _PrefsGotrueAsyncStorage();

class _PrefsLocalStorage extends LocalStorage {
  _PrefsLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(persistSessionKey);
  }

  @override
  Future<bool> hasAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(persistSessionKey);
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(persistSessionKey, persistSessionString);
  }

  @override
  Future<void> removePersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(persistSessionKey);
  }
}

class _PrefsGotrueAsyncStorage extends GotrueAsyncStorage {
  const _PrefsGotrueAsyncStorage();

  static const _prefix = 'gotrue_';

  @override
  Future<String?> getItem({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix$key');
  }

  @override
  Future<void> removeItem({required String key}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', value);
  }
}
