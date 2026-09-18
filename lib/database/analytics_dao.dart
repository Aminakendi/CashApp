import 'dart:io';
import 'package:drift/drift.dart';
import 'database.dart';
import 'tables.dart';
import '../services/notification_service.dart';

part 'analytics_dao.g.dart';

@DriftAccessor(tables: [Transactions, Categories, BudgetNotifications])
class AnalyticsDao extends DatabaseAccessor<AppDatabase> with _$AnalyticsDaoMixin {
  AnalyticsDao(super.db);

  /// Get total spent for a specific category in a specific month
  Future<double> getCategorySpendForMonth(int categoryId, int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('expense') &
        transactions.categoryId.equals(categoryId)
      );

    final result = await query.getSingle();
    return result.read(amountSum) ?? 0.0;
  }

  /// Check budget thresholds and fire notifications
  Future<void> checkBudgetThresholds(int categoryId, DateTime transactionDate) async {
    final category = await (select(categories)..where((c) => c.id.equals(categoryId))).getSingleOrNull();
    if (category == null || category.monthlyBudget == null || category.monthlyBudget! <= 0) return;

    final spent = await getCategorySpendForMonth(categoryId, transactionDate.year, transactionDate.month);
    final percentage = spent / category.monthlyBudget!;
    
    final yearMonth = '${transactionDate.year}-${transactionDate.month.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final isCurrentMonth = transactionDate.year == now.year && transactionDate.month == now.month;

    // Check thresholds: we could hit both 80 and 100 in one jump
    final List<int> thresholdsToTrigger = [];
    if (percentage >= 1.0) {
      thresholdsToTrigger.add(100);
      thresholdsToTrigger.add(80); // In case it jumped, try to log both
    } else if (percentage >= 0.8) {
      thresholdsToTrigger.add(80);
    }

    for (final threshold in thresholdsToTrigger) {
      try {
        await into(budgetNotifications).insert(
          BudgetNotificationsCompanion.insert(
            categoryId: categoryId,
            yearMonth: yearMonth,
            threshold: threshold,
          ),
        );
        // If insert succeeds, it means we haven't fired this threshold for this category+month.
        if (isCurrentMonth && !Platform.environment.containsKey('FLUTTER_TEST')) {
          // The notification uses the threshold percentage to avoid saying '150% of your budget' in an 80% alert.
          await NotificationService().showBudgetAlert(category.name, threshold / 100.0, spent, category.monthlyBudget!);
        }
      } catch (e) {
        // Unique constraint violation (SqliteException) - we already sent this notification.
      }
    }
  }

  /// Get total income for a specific month
  Future<double> getTotalIncome(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('income')
      );

    final result = await query.getSingle();
    return result.read(amountSum) ?? 0.0;
  }

  /// Get total expenses for a specific month, EXPLICITLY excluding transfers
  Future<double> getTotalExpenses(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final amountSum = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('expense')
      );

    final result = await query.getSingle();
    return result.read(amountSum) ?? 0.0;
  }

  /// Get expenses grouped by category for a specific month
  Future<List<CategorySpend>> getCategorySpend(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final amountSum = transactions.amount.sum();
    
    final query = selectOnly(transactions)
      ..addColumns([transactions.categoryId, amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('expense')
      )
      ..groupBy([transactions.categoryId]);

    final rows = await query.get();
    
    // Fetch all categories to map IDs to names
    final allCategories = await select(categories).get();
    final categoryMap = {for (var c in allCategories) c.id: c.name};

    return rows.map((row) {
      final catId = row.read(transactions.categoryId);
      return CategorySpend(
        categoryId: catId,
        categoryName: catId != null ? (categoryMap[catId] ?? 'Unknown') : 'Uncategorized',
        totalSpend: row.read(amountSum) ?? 0.0,
      );
    }).toList();
  }

  /// Watch expenses grouped by category for a specific month
  Stream<List<CategorySpend>> watchCategorySpend(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final amountSum = transactions.amount.sum();
    
    final query = selectOnly(transactions)
      ..addColumns([transactions.categoryId, amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('expense')
      )
      ..groupBy([transactions.categoryId]);

    return query.watch().asyncMap((rows) async {
      final allCategories = await select(categories).get();
      final categoryMap = {for (var c in allCategories) c.id: c.name};

      return rows.map((row) {
        final catId = row.read(transactions.categoryId);
        return CategorySpend(
          categoryId: catId,
          categoryName: catId != null ? (categoryMap[catId] ?? 'Unknown') : 'Uncategorized',
          totalSpend: row.read(amountSum) ?? 0.0,
        );
      }).toList();
    });
  }

  /// Find potential wasted spend: e.g., Counterparties with 3+ expenses under Ksh 300
  Future<List<WastedSpend>> getWastedSpendCandidates(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final txCount = transactions.id.count();
    final txSum = transactions.amount.sum();

    final query = selectOnly(transactions)
      ..addColumns([transactions.counterparty, txCount, txSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('expense') &
        transactions.amount.isSmallerThanValue(300.0)
      )
      ..groupBy([transactions.counterparty]);

    final rows = await query.get();
    return rows.where((row) => (row.read(txCount) ?? 0) >= 3).map((row) {
      return WastedSpend(
        counterparty: row.read(transactions.counterparty) ?? 'Unknown',
        count: row.read(txCount) ?? 0,
        totalSpend: row.read(txSum) ?? 0.0,
      );
    }).toList();
  }

  /// Get total Fuliza usage and repayment for the month
  Future<Map<String, double>> getFulizaStats(int year, int month) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1).subtract(const Duration(milliseconds: 1));

    final amountSum = transactions.amount.sum();
    
    // Usage: 'expense' where subtype is 'fuliza' or counterparty contains 'Fuliza'
    final usageQuery = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.type.equals('expense') &
        (transactions.mpesaSubtype.equals('fuliza') | transactions.counterparty.like('%Fuliza%'))
      );
      
    // Repayment: 'income' or 'expense' where counterparty contains 'Fuliza Repayment'? 
    // Actually, Fuliza repayment is typically a negative/auto-deduction or specifically marked.
    // Assuming subtype 'fuliza' handles it, but let's just use counterparty for simplicity.
    final repaymentQuery = selectOnly(transactions)
      ..addColumns([amountSum])
      ..where(
        transactions.timestamp.isBetweenValues(start, end) &
        transactions.counterparty.like('%Fuliza%') & 
        transactions.counterparty.like('%Repayment%')
      );

    final usageRow = await usageQuery.getSingle();
    final repaymentRow = await repaymentQuery.getSingle();

    return {
      'usage': usageRow.read(amountSum) ?? 0.0,
      'repayment': repaymentRow.read(amountSum) ?? 0.0,
    };
  }
}

class CategorySpend {
  final int? categoryId;
  final String categoryName;
  final double totalSpend;
  CategorySpend({this.categoryId, required this.categoryName, required this.totalSpend});
}

class WastedSpend {
  final String counterparty;
  final int count;
  final double totalSpend;
  WastedSpend({required this.counterparty, required this.count, required this.totalSpend});
}
