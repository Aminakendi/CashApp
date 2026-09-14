import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:mpesa_tracker/database/database.dart';

void main() {
  // ── Helper ─────────────────────────────────────────────────────────────────

  /// Opens a raw sqlite3 database at [path], runs [setup], then closes it.
  void withRawDb(String path, void Function(Database db) setup) {
    final db = sqlite3.open(path);
    try {
      setup(db);
    } finally {
      db.dispose();
    }
  }

  // ── Test 1: v1 → v3 ────────────────────────────────────────────────────────
  test('v1→v3: existing transactions survive notes2 column addition and BudgetNotifications creation', () async {
    final dbFile = File('test_migration_v1_v3.db');
    if (dbFile.existsSync()) dbFile.deleteSync();

    withRawDb(dbFile.path, (db) {
      db.execute('PRAGMA user_version = 1;');
      db.execute('''
        CREATE TABLE categories (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT NOT NULL,
          monthly_budget REAL
        );
      ''');
      db.execute('''
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

      final ts = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      db.execute('''
        INSERT INTO transactions (amount, type, source, mpesa_transaction_code, payment_method, timestamp)
        VALUES (1000.0, 'income', 'manual', 'TEST12345', 'mpesa', $ts);
      ''');
    });

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));
    final txs = await db.select(db.transactions).get();

    expect(txs.length, 1);
    expect(txs.first.mpesaTransactionCode, 'TEST12345');
    expect(txs.first.notes2, null); // v2 column present and nullable for old rows

    // BudgetNotifications table must exist (v3 migration ran)
    final budgetRows = await db.select(db.budgetNotifications).get();
    expect(budgetRows, isEmpty);

    await db.close();
    if (dbFile.existsSync()) dbFile.deleteSync();
  });

  // ── Test 2: v2 → v3 ────────────────────────────────────────────────────────
  test('v2→v3: BudgetNotifications table is created and existing transactions survive', () async {
    final dbFile = File('test_migration_v2_v3.db');
    if (dbFile.existsSync()) dbFile.deleteSync();

    withRawDb(dbFile.path, (db) {
      db.execute('PRAGMA user_version = 2;');
      db.execute('''
        CREATE TABLE categories (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT NOT NULL,
          monthly_budget REAL
        );
      ''');
      db.execute('''
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
          notes2 TEXT,
          payment_method TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          raw_sms_text TEXT
        );
      ''');
      db.execute('''
        CREATE TABLE savings_goals (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          target_amount REAL NOT NULL,
          current_amount REAL NOT NULL DEFAULT 0.0,
          target_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');
      db.execute('''
        CREATE TABLE category_rules (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          pattern TEXT NOT NULL,
          category_id INTEGER NOT NULL REFERENCES categories (id)
        );
      ''');
      db.execute('''
        CREATE TABLE unparsed_messages (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          raw_sms TEXT NOT NULL,
          reason TEXT NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');

      // Insert a category and a transaction referencing it
      db.execute('''
        INSERT INTO categories (id, name, icon) VALUES (2, 'Transport', 'directions_car');
      ''');
      final ts = DateTime(2026, 3, 1).millisecondsSinceEpoch ~/ 1000;
      db.execute('''
        INSERT INTO transactions (amount, type, source, mpesa_transaction_code,
                                  payment_method, timestamp, category_id)
        VALUES (500.0, 'expense', 'mpesa_sms', 'V2TX99999', 'mpesa', $ts, 2);
      ''');
    });

    final db = AppDatabase.forTesting(NativeDatabase(dbFile));

    final txs = await db.select(db.transactions).get();
    expect(txs.length, 1);
    expect(txs.first.mpesaTransactionCode, 'V2TX99999');
    expect(txs.first.categoryId, 2);

    // BudgetNotifications table must exist after migration
    final budgetRows = await db.select(db.budgetNotifications).get();
    expect(budgetRows, isEmpty);

    await db.close();
    if (dbFile.existsSync()) dbFile.deleteSync();
  });

  // ── Test 3: v3 → v4 (Component 1 dedicated test) ──────────────────────────
  //
  // This is the test mandated by the safeguards plan for the categories table
  // recreation. It asserts:
  //   (a) every category row survives with its exact original id preserved
  //   (b) every transactions.category_id that was set before the migration
  //       still resolves to the same category name after it
  test('v3→v4: categories table recreated without AUTOINCREMENT; all categoryId FK references resolve to the same name', () async {
    final dbFile = File('test_migration_v3_v4.db');
    if (dbFile.existsSync()) dbFile.deleteSync();

    // Set of (id, name) pairs we expect to survive unchanged
    const originalCategories = [
      (1, 'Food'),
      (2, 'Transport'),
      (11, 'Other'),
    ];

    withRawDb(dbFile.path, (db) {
      db.execute('PRAGMA user_version = 3;');

      // v3 schema: categories with AUTOINCREMENT (the old form)
      db.execute('''
        CREATE TABLE categories (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT NOT NULL,
          monthly_budget REAL
        );
      ''');
      db.execute('''
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
          notes2 TEXT,
          payment_method TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          raw_sms_text TEXT
        );
      ''');
      db.execute('''
        CREATE TABLE savings_goals (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          target_amount REAL NOT NULL,
          current_amount REAL NOT NULL DEFAULT 0.0,
          target_date INTEGER NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');
      db.execute('''
        CREATE TABLE category_rules (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          pattern TEXT NOT NULL,
          category_id INTEGER NOT NULL REFERENCES categories (id)
        );
      ''');
      db.execute('''
        CREATE TABLE unparsed_messages (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          raw_sms TEXT NOT NULL,
          reason TEXT NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');
      db.execute('''
        CREATE TABLE budget_notifications (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          category_id INTEGER NOT NULL REFERENCES categories (id),
          year_month TEXT NOT NULL,
          threshold INTEGER NOT NULL,
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          UNIQUE (category_id, year_month, threshold)
        );
      ''');

      // Insert a subset of the real default categories using their stable IDs
      for (final (id, name) in originalCategories) {
        db.execute(
          "INSERT INTO categories (id, name, icon) VALUES ($id, '$name', 'test_icon');",
        );
      }

      // Insert transactions referencing each category
      int ts = DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      for (final (catId, _) in originalCategories) {
        db.execute('''
          INSERT INTO transactions (amount, type, source, payment_method, timestamp, category_id)
          VALUES (100.0, 'expense', 'manual', 'mpesa', ${ts++}, $catId);
        ''');
      }
    });

    // Open with Drift — triggers v3→v4 migration
    final db = AppDatabase.forTesting(NativeDatabase(dbFile));

    // (a) Every category must survive with the exact same id and name
    final cats = await db.select(db.categories).get();
    final catById = {for (final c in cats) c.id: c.name};

    for (final (id, name) in originalCategories) {
      expect(catById[id], name,
          reason: 'Category id=$id should still map to "$name" after migration');
    }

    // (b) Every transaction.categoryId must resolve to the correct name —
    //     proving the FK relationship survived the table recreation intact.
    final txs = await db.select(db.transactions).get();
    expect(txs.length, originalCategories.length);

    final expectedNameByCatId = {
      for (final (id, name) in originalCategories) id: name,
    };

    for (final tx in txs) {
      final catId = tx.categoryId;
      expect(catId, isNotNull, reason: 'Transaction categoryId should not be null after migration');
      expect(catById[catId], expectedNameByCatId[catId],
          reason: 'Transaction with categoryId=$catId resolves to wrong category name after migration');
    }

    await db.close();
    if (dbFile.existsSync()) dbFile.deleteSync();
  });
}
