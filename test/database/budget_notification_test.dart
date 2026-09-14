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

  test('Budget threshold jumping inserts both 80 and 100 notifications', () async {
    final catId = await db.into(db.categories).insert(CategoriesCompanion.insert(
      name: 'Food',
      icon: 'restaurant',
      monthlyBudget: const drift.Value(1000.0),
    ));

    final now = DateTime.now();

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 1200,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);

    final notifications = await db.select(db.budgetNotifications).get();
    expect(notifications.length, 2);
    expect(notifications.any((n) => n.threshold == 80), isTrue);
    expect(notifications.any((n) => n.threshold == 100), isTrue);
  });

  test('Unique constraint prevents duplicate notifications and max threshold stays silent', () async {
    final catId = await db.into(db.categories).insert(CategoriesCompanion.insert(
      name: 'Transport',
      icon: 'bus',
      monthlyBudget: const drift.Value(1000.0),
    ));

    final now = DateTime.now();

    // 1. Spend 850 (85%)
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 850,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);

    // 2. Verify 80% is recorded
    var notifications = await db.select(db.budgetNotifications).get();
    expect(notifications.length, 1);
    expect(notifications.first.threshold, 80);

    // 3. Spend another 50 (total 900, still 90%)
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 50,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);

    // 4. Verify still only one notification (no crash due to unique constraint, and no duplicate)
    notifications = await db.select(db.budgetNotifications).get();
    expect(notifications.length, 1);
    expect(notifications.first.threshold, 80);
    
    // 5. Spend 150 (total 1050, 105%)
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 150,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);
    
    // 6. Verify 100% is now added, total 2 notifications
    notifications = await db.select(db.budgetNotifications).get();
    expect(notifications.length, 2);
    
    // 7. Spend another 100 (total 1150)
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 100,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);
    
    // 8. Verify STILL only 2 notifications (no 3rd notification fired!)
    notifications = await db.select(db.budgetNotifications).get();
    expect(notifications.length, 2);
  });
}
