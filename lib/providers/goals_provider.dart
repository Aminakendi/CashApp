import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../database/database.dart';
import 'db_provider.dart';

final savingsGoalsProvider = StreamProvider<List<SavingsGoal>>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.savingsGoals).watch();
});

final goalProvider = StreamProvider.family<SavingsGoal?, int>((ref, id) {
  final db = ref.watch(dbProvider);
  return (db.select(db.savingsGoals)..where((g) => g.id.equals(id))).watchSingleOrNull();
});

final goalsNotifierProvider = Provider<GoalsNotifier>((ref) {
  return GoalsNotifier(ref.watch(dbProvider));
});

class GoalsNotifier {
  final AppDatabase _db;

  GoalsNotifier(this._db);

  Future<void> createGoal(String name, double targetAmount, DateTime targetDate) async {
    await _db.into(_db.savingsGoals).insert(
      SavingsGoalsCompanion.insert(
        name: name,
        targetAmount: targetAmount,
        targetDate: targetDate,
      ),
    );
  }

  Future<void> addContribution(int goalId, double amount) async {
    await (_db.update(_db.savingsGoals)..where((g) => g.id.equals(goalId))).write(
      SavingsGoalsCompanion.custom(
        currentAmount: _db.savingsGoals.currentAmount + Variable<double>(amount),
      ),
    );
  }
}
