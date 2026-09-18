import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String tempPath;
  FakePathProviderPlatform(this.tempPath);

  @override
  Future<String?> getApplicationDocumentsDirectoryPath() async => tempPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempPath;

  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('backup app.db before migration', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        return 'dummy_key';
      },
    );

    final tempDir = Directory.systemTemp.createTempSync('backup_test');
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);

    final dbFile = File(p.join(tempDir.path, 'app.db'));
    final backupFile = File(p.join(tempDir.path, 'app.db.bak'));

    // Create a dummy v4 database (with savings_goals table, no icon_name column)
    final rawDb = sqlite3.open(dbFile.path);
    // Write fake data so file is not empty
    rawDb.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL, monthly_budget REAL NULL);');
    rawDb.execute('INSERT INTO categories (id, name, icon) VALUES (1, "Test", "icon");');
    rawDb.execute('CREATE TABLE savings_goals (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, target_amount REAL NOT NULL, current_amount REAL NOT NULL DEFAULT 0.0, target_date INTEGER NOT NULL, created_at INTEGER NOT NULL DEFAULT (strftime(\'%s\', \'now\')));');
    rawDb.execute('INSERT INTO savings_goals (name, target_amount, target_date) VALUES (\'Vacation\', 50000.0, 1893456000);');
    rawDb.execute('PRAGMA user_version = 4;');
    rawDb.dispose();

    final sizeBefore = dbFile.lengthSync();
    print('Size of app.db before migration: $sizeBefore bytes');

    // Trigger migration by opening AppDatabase
    final db = AppDatabase();
    
    // Wait for the connection to be established and migration to run
    await db.customSelect('SELECT 1').get();
    await db.close();

    final backupExists = backupFile.existsSync();
    print('app.db.bak exists: $backupExists');
    
    if (backupExists) {
      final sizeAfter = backupFile.lengthSync();
      print('Size of app.db.bak: $sizeAfter bytes');
      expect(sizeAfter, greaterThan(0));
    } else {
      fail('Backup file was not created');
    }
    
    tempDir.deleteSync(recursive: true);
  });
}
