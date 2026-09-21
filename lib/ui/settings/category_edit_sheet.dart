import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:mpesa_tracker/database/database.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';
import 'package:mpesa_tracker/theme/app_theme.dart';
import 'package:mpesa_tracker/ui/settings/category_icon_picker.dart';

class CategoryEditSheet extends ConsumerStatefulWidget {
  final Category? category; // If null, adding a new category

  const CategoryEditSheet({super.key, this.category});

  @override
  ConsumerState<CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<CategoryEditSheet> {
  late TextEditingController _nameController;
  late TextEditingController _budgetController;
  late String _selectedIconHex;

  bool get _isEditing => widget.category != null;
  bool get _isDefault => _isEditing && widget.category!.id < 1000;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _budgetController = TextEditingController(
      text: widget.category?.monthlyBudget?.toStringAsFixed(0) ?? '',
    );
    // Default to shopping_bag if none
    _selectedIconHex = widget.category?.icon ?? Icons.shopping_bag.codePoint.toRadixString(16);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _pickIcon() async {
    if (_isDefault) return; // Cannot edit default icons
    
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => const CategoryIconPicker(),
    );
    if (result != null) {
      setState(() {
        _selectedIconHex = result;
      });
    }
  }

  void _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final budgetText = _budgetController.text.replaceAll(',', '');
    final budget = budgetText.isNotEmpty ? double.tryParse(budgetText) : null;

    final db = ref.read(dbProvider);

    try {
      if (_isEditing) {
        final updated = widget.category!.copyWith(
          name: _isDefault ? widget.category!.name : name, // Preserve default name
          icon: _isDefault ? widget.category!.icon : _selectedIconHex, // Preserve default icon
          monthlyBudget: drift.Value(budget),
        );
        await db.categoryDao.updateCategory(updated);
      } else {
        final newCat = CategoriesCompanion.insert(
          name: name,
          icon: _selectedIconHex,
          monthlyBudget: drift.Value(budget),
        );
        await db.categoryDao.insertCategory(newCat);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Category updated' : 'Category added')),
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
            _isEditing ? 'Edit Category' : 'New Category',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          Row(
            children: [
              InkWell(
                onTap: _pickIcon,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Icon(
                    IconData(int.parse(_selectedIconHex, radix: 16), fontFamily: 'MaterialIcons'),
                    size: 32,
                    color: _isDefault ? Colors.grey : AppTheme.primaryPink,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  enabled: !_isDefault,
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          if (_isDefault)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Name and icon cannot be changed for default categories.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
            
          const SizedBox(height: 16),
          TextField(
            controller: _budgetController,
            decoration: const InputDecoration(
              labelText: 'Monthly Budget (Optional)',
              border: OutlineInputBorder(),
              prefixText: 'Ksh ',
            ),
            keyboardType: TextInputType.number,
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
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPink,
                  foregroundColor: Colors.white,
                ),
                child: const Text('SAVE'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
