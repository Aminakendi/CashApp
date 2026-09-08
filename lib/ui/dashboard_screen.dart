import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/db_provider.dart';
import '../database/database.dart';
import '../database/seeder.dart';
import 'manual_entry_screen.dart';
import 'permission_onboarding_dialog.dart';
import '../services/sms_sync_manager.dart';
import '../services/sms_ingestion_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSeeded = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final db = ref.read(dbProvider);
    await DatabaseSeeder.seedCategoriesIfEmpty(db);

    final hasSmsPermission = await Permission.sms.isGranted;
    if (hasSmsPermission) {
      await SmsSyncManager.initialize(db);
      // Attempt to reprocess any unparsed messages with updated parser rules
      await SmsSyncManager.reprocessUnparsedMessages(db);
    }
    
    // DEBUG DIAGNOSTICS removed

    if (mounted) {
      setState(() {
        _isSeeded = true;
      });

      // Show onboarding if permission has not been requested yet
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          PermissionOnboardingSheet.showIfNeeded(context, () {});
        }
      });
    }
  }
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
                    // Targeted column update to avoid clobbering concurrent background edits
                    await (db.update(db.transactions)
                          ..where((t) => t.id.equals(tx.id)))
                        .write(TransactionsCompanion(
                            categoryId: Value(selectedId)));

                    // Active learning: close the loop!
                    if (tx.counterparty != null &&
                        tx.counterparty!.isNotEmpty) {
                      await SmsIngestionService.learnCategoryRule(
                        db,
                        tx.counterparty!,
                        selectedId!,
                      );
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
  Widget build(BuildContext context) {
    final db = ref.watch(dbProvider);
    final currencyFormatter =
        NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 2);
    final dateFormatter = DateFormat.yMMMd().add_jm();

    return Scaffold(
      appBar: AppBar(
        title: const Text('M-Pesa Tracker'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: !_isSeeded 
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<TransactionEntry>>(
        stream: (db.select(db.transactions)
              ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
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
            return const Center(child: Text('No transactions yet.'));
          }

          return ListView.builder(
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isIncome = tx.type == 'income';
              final isTransfer = tx.type == 'transfer';

              Color amountColor;
              if (isIncome) {
                amountColor = Colors.green;
              } else if (isTransfer) {
                amountColor = Colors.grey;
              } else {
                amountColor = Colors.redAccent; // Semantic warning color
              }

              final sign = isIncome ? '+' : (isTransfer ? '' : '-');

              return ListTile(
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
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Transaction'),
                            content: const Text('Are you sure you want to delete this transaction?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ManualEntryScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
    );
  }
}
