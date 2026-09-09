import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;

import '../../providers/db_provider.dart';
import '../../theme/app_theme.dart';
import '../../database/database.dart';
import '../../database/analytics_dao.dart';

class BudgetTab extends ConsumerStatefulWidget {
  const BudgetTab({super.key});

  @override
  ConsumerState<BudgetTab> createState() => _BudgetTabState();
}

class _BudgetTabState extends ConsumerState<BudgetTab> {
  final DateTime _currentMonth = DateTime.now();

  Future<void> _editBudget(BuildContext context, AppDatabase db, Category cat) async {
    final controller = TextEditingController(
      text: (cat.monthlyBudget != null && cat.monthlyBudget! > 0) ? cat.monthlyBudget.toString() : '',
    );
    String? errorText;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Set Budget: ${cat.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monthly Budget Amount',
                      hintText: 'e.g. 5000',
                      prefixText: 'Ksh ',
                      enabledBorder: errorText != null
                          ? OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                              borderSide: const BorderSide(color: AppTheme.semanticAmber, width: 1),
                            )
                          : null, // fallback to theme
                      focusedBorder: errorText != null
                          ? OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
                              borderSide: const BorderSide(color: AppTheme.semanticAmber, width: 1),
                            )
                          : null, // fallback to theme
                    ),
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppTheme.semanticAmber, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            errorText!,
                            style: const TextStyle(color: AppTheme.semanticAmber, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    // Clear budget
                    await (db.update(db.categories)..where((c) => c.id.equals(cat.id)))
                        .write(const CategoriesCompanion(monthlyBudget: drift.Value(null)));
                    if (context.mounted) Navigator.pop(context);
                    setState(() {});
                  },
                  child: const Text('Clear', style: TextStyle(color: AppTheme.semanticRed)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final amount = double.tryParse(controller.text);
                    if (amount == null || amount <= 0) {
                      setDialogState(() {
                        errorText = 'Budget must be greater than Ksh 0';
                      });
                    } else {
                      await (db.update(db.categories)..where((c) => c.id.equals(cat.id)))
                          .write(CategoriesCompanion(monthlyBudget: drift.Value(amount)));
                      if (context.mounted) Navigator.pop(context);
                      setState(() {});
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _getIconForName(String iconName) {
    switch (iconName) {
      case 'restaurant': return Icons.restaurant;
      case 'directions_car': return Icons.directions_car;
      case 'home': return Icons.home;
      case 'bolt': return Icons.bolt;
      case 'phone_android': return Icons.phone_android;
      case 'shopping_cart': return Icons.shopping_cart;
      case 'movie': return Icons.movie;
      case 'local_hospital': return Icons.local_hospital;
      case 'money_off': return Icons.money_off;
      case 'savings': return Icons.savings;
      default: return Icons.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(dbProvider);
    final currencyFormatter = NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Monthly Budgets'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: FutureBuilder(
        future: Future.wait([
          db.select(db.categories).get(),
          db.analyticsDao.getCategorySpend(_currentMonth.year, _currentMonth.month),
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }

          final data = snapshot.data as List<dynamic>;
          final categories = data[0] as List<Category>;
          final categorySpend = data[1] as List<CategorySpend>;

          // Map spends by category ID
          final spendMap = {for (var s in categorySpend) s.categoryId: s.totalSpend};

          // Separate into budgeted and unbudgeted, treating 0 as null
          final budgeted = categories.where((c) => c.monthlyBudget != null && c.monthlyBudget! > 0).toList();
          final unbudgeted = categories.where((c) => c.monthlyBudget == null || c.monthlyBudget! <= 0).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (budgeted.isNotEmpty) ...[
                const Text('Budgeted Categories', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...budgeted.map((cat) {
                  final spend = spendMap[cat.id] ?? 0.0;
                  final budget = cat.monthlyBudget!;
                  final percent = budget > 0 ? (spend / budget) : 0.0;
                  
                  Color progressColor;
                  if (percent < 0.8) {
                    progressColor = AppTheme.semanticGreen;
                  } else if (percent <= 1.0) {
                    progressColor = AppTheme.semanticAmber;
                  } else {
                    progressColor = AppTheme.semanticRed;
                  }

                  return Card(
                    color: AppTheme.surface,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _editBudget(context, db, cat),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: progressColor.withValues(alpha: 0.1),
                                  child: Icon(_getIconForName(cat.icon), color: progressColor),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(cat.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                      Text('${currencyFormatter.format(spend)} / ${currencyFormatter.format(budget)}', style: const TextStyle(color: AppTheme.textSecondary)),
                                    ],
                                  ),
                                ),
                                Text('${(percent * 100).toStringAsFixed(0)}%', style: TextStyle(color: progressColor, fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: percent > 1.0 ? 1.0 : percent,
                                backgroundColor: AppTheme.textDisabled.withValues(alpha: 0.2),
                                color: progressColor,
                                minHeight: 8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
              ],
              
              if (unbudgeted.isNotEmpty) ...[
                const Text('Unbudgeted Categories', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ...unbudgeted.map((cat) {
                  final spend = spendMap[cat.id] ?? 0.0;
                  
                  return Card(
                    color: AppTheme.surface,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _editBudget(context, db, cat),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.textDisabled.withValues(alpha: 0.1),
                          child: Icon(_getIconForName(cat.icon), color: AppTheme.textSecondary),
                        ),
                        title: Text(cat.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: const Text('No budget set', style: TextStyle(color: AppTheme.textSecondary)),
                        trailing: spend > 0 
                            ? Text('Spent: ${currencyFormatter.format(spend)}', style: const TextStyle(color: AppTheme.textSecondary))
                            : null,
                      ),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
