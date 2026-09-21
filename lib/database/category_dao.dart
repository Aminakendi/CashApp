import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:mpesa_tracker/database/tables.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories, Transactions])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(super.db);

  static const String _kLastCustomCategoryIdKey = 'last_custom_category_id';
  static const int _kInitialCustomCategoryId = 1000;

  Future<int> insertCategory(CategoriesCompanion category) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Default to 999 so the first increment returns 1000.
    int lastId = prefs.getInt(_kLastCustomCategoryIdKey) ?? (_kInitialCustomCategoryId - 1);
    
    // Increment to get the new ID
    final newId = lastId + 1;
    
    // Insert into DB
    final companionWithId = category.copyWith(id: Value(newId));
    await into(categories).insert(companionWithId);
    
    // Persist new last ID only if insertion succeeded
    await prefs.setInt(_kLastCustomCategoryIdKey, newId);
    
    return newId;
  }

  Future<void> updateCategory(Category category) async {
    await update(categories).replace(category);
  }

  Future<void> deleteCategory(int id, {int? reassignToId}) async {
    if (id < 1000) {
      throw StateError('Cannot delete default categories (id < 1000)');
    }

    final usageCount = await categoryTransactionsCount(id);
    
    if (usageCount > 0) {
      if (reassignToId == null) {
        throw StateError('Cannot delete category $id: It is used by $usageCount transactions and no reassignment ID was provided.');
      }
      
      // Perform bulk reassignment and deletion in a single transaction
      await transaction(() async {
        // 1. Reassign transactions
        await (update(transactions)..where((t) => t.categoryId.equals(id)))
            .write(TransactionsCompanion(categoryId: Value(reassignToId)));
            
        // 2. Delete category
        await (delete(categories)..where((c) => c.id.equals(id))).go();
      });
    } else {
      // 0 usages, safe to delete immediately
      await (delete(categories)..where((c) => c.id.equals(id))).go();
    }
  }

  Future<int> categoryTransactionsCount(int categoryId) async {
    final countExp = transactions.id.count();
    final query = selectOnly(transactions)
      ..addColumns([countExp])
      ..where(transactions.categoryId.equals(categoryId));
      
    final result = await query.map((row) => row.read(countExp)).getSingle();
    return result ?? 0;
  }

  Stream<List<Category>> watchAllCategories() {
    return (select(categories)..orderBy([(c) => OrderingTerm(expression: c.name)])).watch();
  }
}
