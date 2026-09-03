import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage();
  static const _keyAlias = 'db_encryption_key';
  static const _keyInitFlag = 'mpesa_tracker_db_initialized';

  static Future<String> getEncryptionKey() async {
    String? key = await _storage.read(key: _keyAlias);
    
    if (key == null) {
      final prefs = await SharedPreferences.getInstance();
      final hasBeenInitialized = prefs.getBool(_keyInitFlag) ?? false;
      
      if (hasBeenInitialized) {
        throw StateError(
          'Database encryption key is missing but the database was previously initialized. '
          'This likely means the device secure storage was wiped or restored without keys. '
          'Local data may be inaccessible.'
        );
      }
      
      key = _generateEncryptionKey();
      await _storage.write(key: _keyAlias, value: key);
      await prefs.setBool(_keyInitFlag, true);
    }
    return key;
  }

  static String _generateEncryptionKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }
}
