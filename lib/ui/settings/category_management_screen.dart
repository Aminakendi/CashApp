import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:mpesa_tracker/theme/app_theme.dart';
import 'package:mpesa_tracker/ui/settings/category_icon_resolver.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';
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
          
          final defaultCategories = categories.where((c) => c.id < 1000).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final customCategories = categories.where((c) => c.id >= 1000).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          
          return ListView(
            padding: const EdgeInsets.only(bottom: 96), // Prevents FAB overlap
            children: [
              if (defaultCategories.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'DEFAULT CATEGORIES', 
                    style: TextStyle(
                      color: Colors.grey, 
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    )
                  ),
                ),
                ...defaultCategories.map((c) => _buildCategoryTile(context, ref, c, true)),
              ],
              if (customCategories.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'YOUR CATEGORIES', 
                    style: TextStyle(
                      color: Colors.grey, 
                      fontSize: 12, 
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    )
                  ),
                ),
                ...customCategories.map((c) => _buildCategoryTile(context, ref, c, false)),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'category_fab',
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

  Widget _buildCategoryTile(BuildContext context, WidgetRef ref, Category category, bool isDefault) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.white.withOpacity(0.05),
        child: Icon(
          CategoryIconResolver.resolve(category.icon),
          color: const Color(0xFFFF2B5E), // AppTheme.primaryPink
        ),
      ),
      title: Text(category.name),
      subtitle: Text(category.monthlyBudget != null 
          ? 'Budget: Ksh ${category.monthlyBudget!.toStringAsFixed(0)}' 
          : 'No budget set'),
      trailing: isDefault 
          ? const Icon(Icons.lock_outline, size: 20, color: Colors.white38)
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
  }
}
