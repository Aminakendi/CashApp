import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:mpesa_tracker/database/database.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // SharedPreferences mock for testing
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('default categories have hard-guard against deletion', () async {
    expect(
      () => db.categoryDao.deleteCategory(1),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('Cannot delete default categories'))),
    );
  });

  test('custom category insertion uses 1000+ IDs', () async {
    final cat1 = CategoriesCompanion.insert(name: 'Custom 1', icon: 'e000');
    final cat2 = CategoriesCompanion.insert(name: 'Custom 2', icon: 'e000');

    final id1 = await db.categoryDao.insertCategory(cat1);
    final id2 = await db.categoryDao.insertCategory(cat2);

    expect(id1, 1000);
    expect(id2, 1001);

    // Verify it was actually inserted
    final storedCats = await db.select(db.categories).get();
    expect(storedCats.any((c) => c.id == 1000 && c.name == 'Custom 1'), isTrue);
  });

  test('delete custom category with NO transactions deletes immediately', () async {
    final cat1 = CategoriesCompanion.insert(name: 'Custom 1', icon: 'e000');
    final id1 = await db.categoryDao.insertCategory(cat1);

    await db.categoryDao.deleteCategory(id1);

    final storedCats = await db.select(db.categories).get();
    expect(storedCats.any((c) => c.id == id1), isFalse);
  });

  test('delete custom category WITH transactions throws if no reassignment provided', () async {
    final cat1 = CategoriesCompanion.insert(name: 'Custom 1', icon: 'e000');
    final id1 = await db.categoryDao.insertCategory(cat1);

    // Add a transaction
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 100.0,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(id1),
      paymentMethod: 'cash',
      timestamp: DateTime.now(),
    ));

    expect(
      () => db.categoryDao.deleteCategory(id1),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('no reassignment ID was provided'))),
    );
  });

  test('delete custom category WITH transactions reassigns bulk correctly', () async {
    final cat1 = CategoriesCompanion.insert(name: 'Custom 1', icon: 'e000');
    final cat2 = CategoriesCompanion.insert(name: 'Custom 2', icon: 'e000');
    final id1 = await db.categoryDao.insertCategory(cat1);
    final id2 = await db.categoryDao.insertCategory(cat2);

    // Add 2 transactions to cat1
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 100.0,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(id1),
      paymentMethod: 'cash',
      timestamp: DateTime.now(),
    ));
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
      amount: 200.0,
      type: 'expense',
      source: 'manual',
      categoryId: drift.Value(id1),
      paymentMethod: 'cash',
      timestamp: DateTime.now(),
    ));

    // Delete cat1 and reassign to cat2
    await db.categoryDao.deleteCategory(id1, reassignToId: id2);

    // Verify cat1 is gone
    final storedCats = await db.select(db.categories).get();
    expect(storedCats.any((c) => c.id == id1), isFalse);
    expect(storedCats.any((c) => c.id == id2), isTrue);

    // Verify both transactions now belong to cat2
    final storedTxs = await db.select(db.transactions).get();
    expect(storedTxs.length, 2);
    expect(storedTxs.every((t) => t.categoryId == id2), isTrue);
  });
}
