import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';

class CategoryReassignSheet extends ConsumerStatefulWidget {
  final Category category;
  final int transactionCount;

  const CategoryReassignSheet({
    super.key,
    required this.category,
    required this.transactionCount,
  });

  @override
  ConsumerState<CategoryReassignSheet> createState() => _CategoryReassignSheetState();
}

class _CategoryReassignSheetState extends ConsumerState<CategoryReassignSheet> {
  int? _selectedCategoryId;

  void _confirmDeletion() async {
    if (_selectedCategoryId == null) return;
    
    final db = ref.read(dbProvider);
    try {
      await db.categoryDao.deleteCategory(
        widget.category.id,
        reassignToId: _selectedCategoryId,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category deleted and transactions reassigned')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(dbProvider);
    
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Delete ${widget.category.name}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'This category is used by ${widget.transactionCount} transactions. '
            'Please select another category to reassign them to before deleting.',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          const Text('Reassign to:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FutureBuilder<List<Category>>(
            future: db.select(db.categories).get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final otherCategories = snapshot.data!
                  .where((c) => c.id != widget.category.id)
                  .toList();
                  
              return DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                value: _selectedCategoryId,
                hint: const Text('Select a category'),
                items: otherCategories.map((c) {
                  return DropdownMenuItem<int>(
                    value: c.id,
                    child: Row(
                      children: [
                        Text(
                          String.fromCharCode(int.parse(c.icon, radix: 16)),
                          style: const TextStyle(fontFamily: 'MaterialIcons'),
                        ),
                        const SizedBox(width: 8),
                        Text(c.name),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedCategoryId = val;
                  });
                },
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CANCEL'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectedCategoryId == null ? null : _confirmDeletion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('DELETE CATEGORY'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
