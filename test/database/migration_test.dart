import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:mpesa_tracker/database/database.dart';

void main() {
  test('Database migration preserves existing data', () async {
    final dbFile = File('test_migration.db');
    if (dbFile.existsSync()) dbFile.deleteSync();

    // 1. Setup v1
    // We create the v1 schema manually via raw SQL to simulate an older app version.
    // If we used db1.createMigrator().createAll(), it would create the current (v2) schema directly.
    final db1 = sqlite3.open(dbFile.path);
    db1.execute('PRAGMA user_version = 1;');
    db1.execute('''
      CREATE TABLE categories (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        monthly_budget REAL
      );
    ''');
    db1.execute('''
      CREATE TABLE transactions (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        source TEXT NOT NULL,
        mpesa_transaction_code TEXT UNIQUE,
        mpesa_subtype TEXT,
        counterparty TEXT,
        category_id INTEGER REFERENCES categories (id),
        note TEXT,
        payment_method TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        raw_sms_text TEXT
      );
    ''');

    // Insert a mock v1 transaction
    final timestamp = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
    db1.execute('''
      INSERT INTO transactions (amount, type, source, mpesa_transaction_code, payment_method, timestamp)
      VALUES (1000.0, 'income', 'manual', 'TEST12345', 'mpesa', $timestamp);
    ''');
    db1.dispose();

    // 2. Reopen with v2 schema (Drift will automatically detect user_version=1 and run onUpgrade to schemaVersion=2)
    final db2 = AppDatabase.forTesting(NativeDatabase(dbFile));

    // Ensure database is opened and migration completes by running a query
    final txs = await db2.select(db2.transactions).get();

    // Verify data survived and new schema column is present
    expect(txs.length, 1);
    expect(txs.first.mpesaTransactionCode, 'TEST12345');
    // Ensure the new v2 column exists and is nullable (null for existing v1 rows)
    expect(txs.first.notes2, null);

    await db2.close();
    if (dbFile.existsSync()) dbFile.deleteSync();
  });
}
