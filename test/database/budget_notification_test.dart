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

  test('Budget threshold jumping inserts both 80 and 100 notifications and history', () async {
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
    // Check AppNotifications history
    final history = await db.select(db.appNotifications).get();
    expect(history.length, 2);
    expect(history.every((h) => h.type == 'budget_threshold'), isTrue);
    expect(history.first.body, contains('80%')); // Written first (oldest)
    expect(history.last.body, contains('100%')); // Written second (newest)
  });

  test('80% writes one row, repeat writes none, 100% writes second row', () async {
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

    var history = await db.select(db.appNotifications).get();
    expect(history.length, 1);
    expect(history.first.title, 'Budget Alert: Transport');
    expect(history.first.body, contains('80%'));

    // 2. Spend another 50 (total 900, still 90%)
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 50,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);

    // Verify repeat writes none
    history = await db.select(db.appNotifications).get();
    expect(history.length, 1);
    
    // 3. Spend 150 (total 1050, 105%)
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 150,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);
    
    // Verify 100% is now added, total 2 notifications
    history = await db.select(db.appNotifications).get();
    expect(history.length, 2);
    expect(history.last.body, contains('100%')); // The latest inserted is 100%
  });
  
  test('A past-month transaction writes no history or notification', () async {
    final catId = await db.into(db.categories).insert(CategoriesCompanion.insert(
      name: 'Rent',
      icon: 'home',
      monthlyBudget: const drift.Value(1000.0),
    ));

    final now = DateTime.now();
    final past = DateTime(now.year, now.month - 1, 15);

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 1200,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: past,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, past);

    // Dedup table still gets it
    final dedup = await db.select(db.budgetNotifications).get();
    expect(dedup.length, 2); // 80 and 100
    
    // But history is empty because it's past month
    final history = await db.select(db.appNotifications).get();
    expect(history, isEmpty);
  });
  
  test('201 inserts leave exactly 200 rows', () async {
    // Manually insert 200 rows
    for (int i = 0; i < 200; i++) {
      await db.into(db.appNotifications).insert(AppNotificationsCompanion.insert(
        type: 'test',
        title: 'Title $i',
        body: 'Body $i',
      ));
    }
    
    final catId = await db.into(db.categories).insert(CategoriesCompanion.insert(
      name: 'Entertainment',
      icon: 'movie',
      monthlyBudget: const drift.Value(1000.0),
    ));

    final now = DateTime.now();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 850,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    await db.analyticsDao.checkBudgetThresholds(catId, now);
    
    final history = await db.select(db.appNotifications).get();
    expect(history.length, 200); // 200 total limit
    
    // The very first one 'Title 0' should have been deleted (it has id 1)
    final firstTitle = history.firstWhere((h) => h.title == 'Title 0', orElse: () => AppNotification(
      id: -1, type: '', title: 'not found', body: '', categoryId: null, createdAt: now, isRead: false
    ));
    expect(firstTitle.title, 'not found');
  });

  test('Ingestion still succeeds when history insert is forced to fail', () async {
    final catId = await db.into(db.categories).insert(CategoriesCompanion.insert(
      name: 'Utilities',
      icon: 'bolt',
      monthlyBudget: const drift.Value(1000.0),
    ));

    // Force failure by dropping the AppNotifications table completely
    await db.customStatement('DROP TABLE app_notifications;');

    final now = DateTime.now();
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 850,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(catId),
      paymentMethod: 'mpesa',
      timestamp: now,
    ));

    // This should not throw
    await db.analyticsDao.checkBudgetThresholds(catId, now);

    // Dedup table should still have the 80% entry
    final dedup = await db.select(db.budgetNotifications).get();
    expect(dedup.length, 1);
    expect(dedup.first.threshold, 80);
  });
}
