import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyStore {
  static const _storage = FlutterSecureStorage();
  static const _keyAlias = 'db_encryption_key';

  static Future<String> getEncryptionKey() async {
    String? key = await _storage.read(key: _keyAlias);
    if (key == null) {
      key = _generateEncryptionKey();
      await _storage.write(key: _keyAlias, value: key);
    }
    return key;
  }

  static String _generateEncryptionKey() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64UrlEncode(values);
  }
}
