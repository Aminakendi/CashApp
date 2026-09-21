import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:mpesa_tracker/providers/database_provider.dart';
import 'package:mpesa_tracker/ui/settings/category_edit_sheet.dart';
import 'package:mpesa_tracker/ui/settings/category_reassign_sheet.dart';

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  void _deleteCategory(BuildContext context, WidgetRef ref, Category category) async {
    if (category.id < 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete default categories')),
      );
      return;
    }

    final db = ref.read(dbProvider);
    final count = await db.categoryDao.categoryTransactionsCount(category.id);

    if (count > 0) {
      if (context.mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => CategoryReassignSheet(category: category, transactionCount: count),
        );
      }
    } else {
      await db.categoryDao.deleteCategory(category.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
      ),
      body: StreamBuilder<List<Category>>(
        stream: db.categoryDao.watchAllCategories(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final categories = snapshot.data!;
          
          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isDefault = category.id < 1000;
              
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    String.fromCharCode(int.parse(category.icon, radix: 16)),
                    style: const TextStyle(fontFamily: 'MaterialIcons'),
                  ),
                ),
                title: Text(category.name),
                subtitle: Text(category.monthlyBudget != null 
                    ? 'Budget: Ksh ${category.monthlyBudget!.toStringAsFixed(0)}' 
                    : 'No budget set'),
                trailing: isDefault 
                    ? const Icon(Icons.lock_outline, size: 20)
                    : IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _deleteCategory(context, ref, category),
                      ),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => CategoryEditSheet(category: category),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (ctx) => const CategoryEditSheet(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
