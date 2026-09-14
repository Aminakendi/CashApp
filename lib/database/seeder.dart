import 'package:drift/drift.dart' as drift;

import 'database.dart';
import '../services/sms_ingestion_service.dart';

class DatabaseSeeder {
  static const List<Map<String, String>> _defaultCategories = [
    {'name': 'Food', 'icon': 'restaurant'},
    {'name': 'Transport', 'icon': 'directions_car'},
    {'name': 'Rent', 'icon': 'home'},
    {'name': 'Utilities', 'icon': 'bolt'},
    {'name': 'Airtime/Data', 'icon': 'phone_android'},
    {'name': 'Shopping', 'icon': 'shopping_cart'},
    {'name': 'Entertainment', 'icon': 'movie'},
    {'name': 'Health', 'icon': 'local_hospital'},
    {'name': 'Fuliza/Debt', 'icon': 'money_off'},
    {'name': 'Savings/Investment', 'icon': 'savings'},
    {'name': 'Other', 'icon': 'category'},
  ];

  /// Known counterparty patterns established by the user before the data wipe.
  /// More specific patterns must come BEFORE broader ones (e.g. "SAFARICOM DATA"
  /// before "SAFARICOM") because resolveCategoryForText returns on first match.
  static const List<Map<String, String>> _defaultCategoryRules = [
    // Transport
    {'pattern': 'ZURI GENESIS', 'category': 'Transport'},
    // Utilities
    {'pattern': 'MOBALI SOLUTION', 'category': 'Utilities'},
    // Airtime/Data — specific variants first
    {'pattern': 'SAFARICOM DATA', 'category': 'Airtime/Data'},
    {'pattern': 'SAFARICON DATA', 'category': 'Airtime/Data'},
    {'pattern': 'SAFARICOM', 'category': 'Airtime/Data'},
    {'pattern': 'SAFARICON', 'category': 'Airtime/Data'},
    // Shopping
    {'pattern': 'NAIVAS', 'category': 'Shopping'},
    {'pattern': 'CARREFOUR', 'category': 'Shopping'},
    // Fuliza/Debt
    {'pattern': 'FULIZA', 'category': 'Fuliza/Debt'},
  ];

  /// Seeds default categories on a fresh install.
  /// Guard: only runs if the Categories table is completely empty.
  static Future<void> seedCategoriesIfEmpty(AppDatabase db) async {
    final count = await db.select(db.categories).get();
    if (count.isEmpty) {
      for (final cat in _defaultCategories) {
        await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: cat['name']!,
            icon: cat['icon']!,
          ),
        );
      }
    }
  }

  /// Seeds the known counterparty→category rules established by the user.
  /// Guard: only runs if CategoryRules table is completely empty.
  /// This means it will never run again once the user has created any rule,
  /// and it will never overwrite manually-created rules.
  static Future<void> seedCategoryRulesIfEmpty(AppDatabase db) async {
    final existing = await db.select(db.categoryRules).get();
    if (existing.isNotEmpty) return;

    final categories = await db.select(db.categories).get();
    final categoryMap = {
      for (var c in categories) c.name.toLowerCase(): c.id
    };

    for (final rule in _defaultCategoryRules) {
      final catId = categoryMap[rule['category']!.toLowerCase()];
      if (catId == null) continue; // safety guard: skip if category name not found

      await db.into(db.categoryRules).insert(
        CategoryRulesCompanion.insert(
          pattern: rule['pattern']!,
          categoryId: catId,
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
}
