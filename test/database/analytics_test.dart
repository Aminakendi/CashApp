import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:drift/drift.dart' as drift;

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('AnalyticsDao getTotalIncome aggregates only income for a given month', () async {
    // 1. Insert some transactions
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 500,
      type: 'income',
      source: 'mpesa_sms',
      paymentMethod: 'mpesa',
      timestamp: DateTime(2023, 10, 5),
    ));

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 1500,
      type: 'income',
      source: 'mpesa_sms',
      paymentMethod: 'mpesa',
      timestamp: DateTime(2023, 10, 15),
    ));

    // Outside the month
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 300,
      type: 'income',
      source: 'mpesa_sms',
      paymentMethod: 'mpesa',
      timestamp: DateTime(2023, 11, 1),
    ));

    // Not an income
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 200,
      type: 'expense',
      source: 'mpesa_sms',
      paymentMethod: 'mpesa',
      timestamp: DateTime(2023, 10, 10),
    ));

    // 2. Query AnalyticsDao
    final totalIncome = await db.analyticsDao.getTotalIncome(2023, 10);

    // 3. Assert
    expect(totalIncome, 2000.0);
  });

  test('AnalyticsDao getTotalExpenses excludes transfers', () async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 500,
      type: 'expense',
      source: 'manual',
      paymentMethod: 'cash',
      timestamp: DateTime(2023, 10, 5),
    ));

    // Transfer should be excluded
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 1500,
      type: 'transfer',
      source: 'mpesa_sms',
      paymentMethod: 'mpesa',
      timestamp: DateTime(2023, 10, 15),
    ));

    final totalExpenses = await db.analyticsDao.getTotalExpenses(2023, 10);
    expect(totalExpenses, 500.0);
  });
}
