import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

import 'tables.dart';
import 'key_store.dart';

import 'analytics_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Transactions, Categories, SavingsGoals, CategoryRules, UnparsedMessages, BudgetNotifications],
  daos: [AnalyticsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.e);

  /// Exposed as a constant so the LazyDatabase factory can read it from a raw
  /// sqlite3 connection (before Drift opens) to decide whether a backup is needed.
  static const int kSchemaVersion = 4;

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(transactions, transactions.notes2);
        }
        if (from < 3) {
          await m.createTable(budgetNotifications);
        }
        if (from < 4) {
          // Recreate the categories table without AUTOINCREMENT.
          //
          // SQLite cannot ALTER a column's PRIMARY KEY constraint in place,
          // so we use the standard rename → create → copy → drop → rename
          // sequence. FK enforcement is disabled for the duration because
          // transactions.category_id references categories, and the reference
          // would be temporarily broken while the table name changes.
          //
          // All existing rows are copied with their original IDs preserved.
          // PRAGMA foreign_key_check runs at the end to assert integrity.
          await customStatement('PRAGMA foreign_keys = OFF');

          await customStatement('''
            CREATE TABLE categories_new (
              "id"             INTEGER NOT NULL,
              "name"           TEXT    NOT NULL,
              "icon"           TEXT    NOT NULL,
              "monthly_budget" REAL    NULL,
              PRIMARY KEY ("id")
            )
          ''');

          await customStatement('''
            INSERT INTO categories_new (id, name, icon, monthly_budget)
            SELECT id, name, icon, monthly_budget FROM categories
          ''');

          await customStatement('DROP TABLE categories');
          await customStatement('ALTER TABLE categories_new RENAME TO categories');

          await customStatement('PRAGMA foreign_keys = ON');

          // Assert no FK violations were introduced by the table swap.
          final violations =
              await customSelect('PRAGMA foreign_key_check').get();
          if (violations.isNotEmpty) {
            throw StateError(
              'FK violations detected after v4 categories migration: '
              '${violations.length} row(s) affected.',
            );
          }
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app.db'));
    final backupFile = File(p.join(dbFolder.path, 'app.db.bak'));

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }

    final cachebase = (await getTemporaryDirectory()).path;
    sqlite3.tempDirectory = cachebase;

    final encryptionKey = await KeyStore.getEncryptionKey();

    // ── Component 2: pre-migration backup ────────────────────────────────
    // Before Drift opens the database and runs any migration, check whether
    // an upgrade is pending. If so, copy app.db → app.db.bak while the file
    // is still in its pre-migration state.
    //
    // This protects against a bad migration during a normal app update.
    // NOTE: it does NOT protect against an OS uninstall — uninstalling wipes
    // the entire app data directory, backup included. Use the JSON export
    // (Settings → Export) for protection against uninstall-level data loss.
    if (file.existsSync()) {
      bool needsBackup = false;
      final rawDb = sqlite3.open(file.path);
      try {
        rawDb.execute("PRAGMA key = '$encryptionKey';");
        final result = rawDb.select('PRAGMA user_version');
        final storedVersion = result.first['user_version'] as int;
        if (storedVersion > 0 && storedVersion < AppDatabase.kSchemaVersion) {
          // Flush WAL into the main file so the backup is self-contained.
          rawDb.execute('PRAGMA wal_checkpoint(FULL)');
          needsBackup = true;
        }
      } catch (_) {
        // If we can't read the version (e.g. wrong key), skip the backup
        // rather than crashing. The migration will still run normally.
      } finally {
        rawDb.dispose();
      }

      if (needsBackup) {
        await file.copy(backupFile.path);
      }
    }
    // ─────────────────────────────────────────────────────────────────────

    return NativeDatabase.createInBackground(file, setup: (rawDb) {
      // Setup SQLCipher encryption key
      rawDb.execute("PRAGMA key = '$encryptionKey';");
    });
  });
}
