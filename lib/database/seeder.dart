import 'package:drift/drift.dart' as drift;

import 'database.dart';
import '../services/sms_ingestion_service.dart';

class DatabaseSeeder {
  /// Default categories with fixed, stable IDs.
  /// IDs 1–11 are reserved for these defaults and must never be reused
  /// for different categories. User-created categories start at ID ≥ 1000.
  static const List<Map<String, dynamic>> _defaultCategories = [
    {'id': 1,  'name': 'Food',               'icon': 'restaurant'},
    {'id': 2,  'name': 'Transport',           'icon': 'directions_car'},
    {'id': 3,  'name': 'Rent',               'icon': 'home'},
    {'id': 4,  'name': 'Utilities',          'icon': 'bolt'},
    {'id': 5,  'name': 'Airtime/Data',       'icon': 'phone_android'},
    {'id': 6,  'name': 'Shopping',           'icon': 'shopping_cart'},
    {'id': 7,  'name': 'Entertainment',      'icon': 'movie'},
    {'id': 8,  'name': 'Health',             'icon': 'local_hospital'},
    {'id': 9,  'name': 'Fuliza/Debt',        'icon': 'money_off'},
    {'id': 10, 'name': 'Savings/Investment', 'icon': 'savings'},
    {'id': 11, 'name': 'Other',              'icon': 'category'},
  ];

  /// Known counterparty→category rules established by the user before the data wipe.
  /// Category IDs are hardcoded (matching the stable IDs above) so this seed
  /// is independent of any name-lookup and cannot drift if category names change.
  ///
  /// More specific patterns must come BEFORE broader ones (e.g. 'SAFARICOM DATA'
  /// before 'SAFARICOM') because resolveCategoryForText returns on first match.
  static const List<Map<String, dynamic>> _defaultCategoryRules = [
    // Transport (id: 2)
    {'pattern': 'ZURI GENESIS',   'categoryId': 2},
    // Utilities (id: 4)
    {'pattern': 'MOBALI SOLUTION','categoryId': 4},
    // Airtime/Data (id: 5) — specific variants before the broad prefix
    {'pattern': 'SAFARICOM DATA', 'categoryId': 5},
    {'pattern': 'SAFARICON DATA', 'categoryId': 5},
    {'pattern': 'SAFARICOM',      'categoryId': 5},
    {'pattern': 'SAFARICON',      'categoryId': 5},
    // Shopping (id: 6)
    {'pattern': 'NAIVAS',         'categoryId': 6},
    {'pattern': 'CARREFOUR',      'categoryId': 6},
    // Fuliza/Debt (id: 9)
    {'pattern': 'FULIZA',         'categoryId': 9},
  ];

  /// Seeds default categories on a fresh install.
  /// Guard: only runs if the Categories table is completely empty.
  /// Each category is inserted with an explicit, stable ID (see _defaultCategories).
  static Future<void> seedCategoriesIfEmpty(AppDatabase db) async {
    final existing = await db.select(db.categories).get();
    if (existing.isNotEmpty) return;

    for (final cat in _defaultCategories) {
      await db.into(db.categories).insert(
        CategoriesCompanion(
          id:   drift.Value(cat['id']   as int),
          name: drift.Value(cat['name'] as String),
          icon: drift.Value(cat['icon'] as String),
        ),
      );
    }
  }

  /// Seeds the known counterparty→category rules established by the user.
  /// Guard: only runs if CategoryRules table is completely empty.
  /// This means it will never run again once the user has created any rule,
  /// and it will never overwrite manually-created rules.
  ///
  /// Category IDs are hardcoded — no name lookup needed.
  static Future<void> seedCategoryRulesIfEmpty(AppDatabase db) async {
    final existing = await db.select(db.categoryRules).get();
    if (existing.isNotEmpty) return;

    for (final rule in _defaultCategoryRules) {
      await db.into(db.categoryRules).insert(
        CategoryRulesCompanion.insert(
          pattern:    rule['pattern']    as String,
          categoryId: rule['categoryId'] as int,
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );
    }
  }

  /// Re-applies the current CategoryRules to ALL existing expense transactions
  /// whose counterparty is non-null. Called once after a rule seed to retroactively
  /// fix categories that defaulted to "Other" during re-ingestion after a data wipe.
  ///
  /// Safe to call repeatedly: only writes if the resolved category differs from
  /// the current one, so already-correct assignments are untouched.
  static Future<int> reapplyCategoryRulesToExistingTransactions(
      AppDatabase db) async {
    final txs = await db.select(db.transactions).get();
    int updatedCount = 0;

    for (final tx in txs) {
      // Only reclassify expenses with a known counterparty
      if (tx.type != 'expense') continue;
      if (tx.counterparty == null || tx.counterparty!.isEmpty) continue;

      final resolvedId =
          await SmsIngestionService.resolveCategoryForText(db, tx.counterparty!);

      // Skip if no better match found, or if the category is already correct
      if (resolvedId == null || resolvedId == tx.categoryId) continue;

      await (db.update(db.transactions)
            ..where((t) => t.id.equals(tx.id)))
          .write(TransactionsCompanion(
              categoryId: drift.Value(resolvedId)));
      updatedCount++;
    }

    return updatedCount;
  }

  /// Retroactively fixes KCB M-PESA transactions that were misclassified as 'unknown'
  /// due to the Safaricom spelling typo ('transfered').
  static Future<int> retroactiveFixKcbTransactions(AppDatabase db) async {
    final txs = await db.select(db.transactions).get();
    int updatedCount = 0;

    for (final tx in txs) {
      if (tx.mpesaSubtype == 'unknown' && tx.rawSmsText != null && tx.rawSmsText!.toLowerCase().contains('kcb m-pesa')) {
        await (db.update(db.transactions)..where((t) => t.id.equals(tx.id))).write(
          TransactionsCompanion(
            type: const drift.Value('transfer'),
            mpesaSubtype: const drift.Value('kcb'),
            counterparty: const drift.Value('KCB M-PESA'),
            categoryId: const drift.Value(null), // Clear category since it's a transfer
          ),
        );
        updatedCount++;
      }
    }

    return updatedCount;
  }
}
