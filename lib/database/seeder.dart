import 'database.dart';

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
}
