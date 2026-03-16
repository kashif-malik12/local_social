import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

LocalStorage createReleaseAuthStorage(String persistSessionKey) =>
    _FileLocalStorage(persistSessionKey: persistSessionKey);

GotrueAsyncStorage createReleasePkceStorage() => const _FileGotrueAsyncStorage();

class _FileLocalStorage extends LocalStorage {
  _FileLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;
  late final File _file = File('${Directory.systemTemp.path}\\$persistSessionKey.json');

  @override
  Future<void> initialize() async {
    if (!await _file.parent.exists()) {
      await _file.parent.create(recursive: true);
    }
  }

  @override
  Future<String?> accessToken() async {
    if (!await _file.exists()) return null;
    return _file.readAsString();
  }

  @override
  Future<bool> hasAccessToken() async => _file.exists();

  @override
  Future<void> persistSession(String persistSessionString) async {
    await initialize();
    await _file.writeAsString(persistSessionString, flush: true);
  }

  @override
  Future<void> removePersistedSession() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}

class _FileGotrueAsyncStorage extends GotrueAsyncStorage {
  const _FileGotrueAsyncStorage();

  File _fileForKey(String key) => File('${Directory.systemTemp.path}\\gotrue_$key.txt');

  @override
  Future<String?> getItem({required String key}) async {
    final file = _fileForKey(key);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> removeItem({required String key}) async {
    final file = _fileForKey(key);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    final file = _fileForKey(key);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    await file.writeAsString(value, flush: true);
  }
}
