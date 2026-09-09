import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;

import '../../providers/db_provider.dart';
import '../../database/database.dart';
import '../../theme/app_theme.dart';
import '../../services/sms_ingestion_service.dart';

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  Future<void> _showEditCategoryDialog(
      BuildContext context, TransactionEntry tx, AppDatabase db) async {
    final categories = await db.select(db.categories).get();
    int? selectedId = tx.categoryId;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Category'),
            content: DropdownButtonFormField<int>(
              initialValue: selectedId,
              decoration: const InputDecoration(labelText: 'Category'),
              items: categories.map((cat) {
                return DropdownMenuItem<int>(
                  value: cat.id,
                  child: Text(cat.name),
                );
              }).toList(),
              onChanged: (val) => setState(() => selectedId = val),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedId != null) {
                    // Update the specific transaction
                    await (db.update(db.transactions)
                          ..where((t) => t.id.equals(tx.id)))
                        .write(TransactionsCompanion(
                            categoryId: drift.Value(selectedId)));

                    if (tx.counterparty != null &&
                        tx.counterparty!.isNotEmpty) {
                      // Learn the rule for future transactions
                      await SmsIngestionService.learnCategoryRule(
                        db,
                        tx.counterparty!,
                        selectedId!,
                      );
                      
                      // Also apply retroactively to all past transactions with the exact same counterparty
                      await (db.update(db.transactions)
                            ..where((t) => t.counterparty.equals(tx.counterparty!)))
                          .write(TransactionsCompanion(
                              categoryId: drift.Value(selectedId)));
                    }
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    final currencyFormatter =
        NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 2);
    final dateFormatter = DateFormat.yMMMd().add_jm();

    return StreamBuilder<List<TransactionEntry>>(
      stream: (db.select(db.transactions)
            ..orderBy([(t) => drift.OrderingTerm.desc(t.timestamp)])
            ..limit(50))
          .watch(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final transactions = snapshot.data ?? [];
        if (transactions.isEmpty) {
          return const Center(child: Text('No transactions yet. Add your first expense.'));
        }

        return ListView.builder(
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index];
            final isIncome = tx.type == 'income';
            final isTransfer = tx.type == 'transfer';

            Color amountColor;
            if (isIncome) {
              amountColor = AppTheme.semanticGreen;
            } else if (isTransfer) {
              amountColor = AppTheme.textDisabled;
            } else {
              amountColor = AppTheme.semanticRed;
            }

            final sign = isIncome ? '+' : (isTransfer ? '' : '-');

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  leading: CircleAvatar(
                    backgroundColor: amountColor.withValues(alpha: 0.1),
                    child: Icon(
                      isIncome
                          ? Icons.arrow_downward
                          : (isTransfer ? Icons.swap_horiz : Icons.arrow_upward),
                      color: amountColor,
                    ),
                  ),
                  title: Text(tx.counterparty ?? tx.note ?? 'Unknown'),
                  subtitle: Text('${dateFormatter.format(tx.timestamp)} • ${tx.source}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$sign${currencyFormatter.format(tx.amount)}',
                        style: TextStyle(
                          color: amountColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.textDisabled),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Transaction'),
                              content: const Text('Are you sure you want to delete this transaction?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false), 
                                  child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.semanticRed),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && context.mounted) {
                            await (db.delete(db.transactions)..where((t) => t.id.equals(tx.id))).go();
                          }
                        },
                      ),
                    ],
                  ),
                  onLongPress: () => _showEditCategoryDialog(context, tx, db),
                  onTap: () => _showEditCategoryDialog(context, tx, db),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
