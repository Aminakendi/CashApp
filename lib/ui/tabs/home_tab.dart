import 'package:flutter/material.dart';
import 'package:mpesa_tracker/ui/settings/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;

import '../../providers/db_provider.dart';
import '../../database/database.dart';
import '../../theme/app_theme.dart';
import '../../services/sms_ingestion_service.dart';


// ─── Filter state ────────────────────────────────────────────────────────────

enum _TypeFilter { all, income, expense, transfer }

enum _MethodFilter { all, mpesa, cash, card }

enum _DateFilter { all, thisMonth, last7Days, custom }

class _FilterState {
  final _TypeFilter type;
  final _MethodFilter method;
  final _DateFilter date;
  final DateTimeRange? customRange;

  const _FilterState({
    this.type = _TypeFilter.all,
    this.method = _MethodFilter.all,
    this.date = _DateFilter.all,
    this.customRange,
  });

  bool get isActive =>
      type != _TypeFilter.all ||
      method != _MethodFilter.all ||
      date != _DateFilter.all;

  _FilterState copyWith({
    _TypeFilter? type,
    _MethodFilter? method,
    _DateFilter? date,
    DateTimeRange? customRange,
    bool clearCustomRange = false,
  }) {
    return _FilterState(
      type: type ?? this.type,
      method: method ?? this.method,
      date: date ?? this.date,
      customRange:
          clearCustomRange ? null : (customRange ?? this.customRange),
    );
  }

  _FilterState reset() => const _FilterState();
}

// ─── Day-group helper ────────────────────────────────────────────────────────

class _DayGroup {
  final DateTime date;
  final List<TransactionEntry> transactions;

  _DayGroup(this.date, this.transactions);

  double get dailySpend => transactions
      .where((t) => t.type == 'expense')
      .fold(0.0, (sum, t) => sum + t.amount);
}

// ─── HomeTab ─────────────────────────────────────────────────────────────────

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> {
  String _searchQuery = '';
  _FilterState _filters = const _FilterState();
  bool _searchActive = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Filtering logic ──────────────────────────────────────────────────────

  Stream<List<TransactionEntry>> _watchFilteredTransactions(AppDatabase db) {
    var query = db.select(db.transactions);
    
    drift.Expression<bool>? filterPredicate;

    void addCondition(drift.Expression<bool> condition) {
      if (filterPredicate == null) {
        filterPredicate = condition;
      } else {
        filterPredicate = filterPredicate! & condition;
      }
    }

    // 1. Search (counterparty or amount string — AND with other filters)
    if (_searchQuery.isNotEmpty) {
      final q = '%${_searchQuery.toLowerCase()}%';
      drift.Expression<bool> searchExpr = db.transactions.counterparty.lower().like(q);
      
      final numericQuery = double.tryParse(_searchQuery.replaceAll(',', ''));
      if (numericQuery != null) {
         searchExpr = searchExpr | db.transactions.amount.equals(numericQuery);
      } else {
         searchExpr = searchExpr | db.transactions.amount.cast<String>().like(q);
      }
      
      addCondition(searchExpr);
    }

    // 2. Type filter
    if (_filters.type != _TypeFilter.all) {
      addCondition(db.transactions.type.equals(_filters.type.name));
    }

    // 3. Payment method filter
    if (_filters.method != _MethodFilter.all) {
      addCondition(db.transactions.paymentMethod.equals(_filters.method.name));
    }

    // 4. Date filter
    if (_filters.date != _DateFilter.all) {
      final now = DateTime.now();
      DateTime? from;
      DateTime? to;

      if (_filters.date == _DateFilter.thisMonth) {
        from = DateTime(now.year, now.month, 1);
        to = now;
      } else if (_filters.date == _DateFilter.last7Days) {
        from = now.subtract(const Duration(days: 7));
        to = now;
      } else if (_filters.date == _DateFilter.custom &&
          _filters.customRange != null) {
        from = _filters.customRange!.start;
        to = _filters.customRange!.end
            .add(const Duration(hours: 23, minutes: 59, seconds: 59));
      }

      if (from != null && to != null) {
        // We use >= and <= to naturally handle boundary inclusivity cleanly.
        addCondition(
            db.transactions.timestamp.isBiggerOrEqualValue(from) &
            db.transactions.timestamp.isSmallerOrEqualValue(to)
        );
      }
    }

    if (filterPredicate != null) {
      query.where((t) => filterPredicate!);
    }

    query.orderBy([(t) => drift.OrderingTerm.desc(t.timestamp)]);
    query.limit(50); // Keep limit strictly at 50 as requested
    return query.watch();
  }

  List<_DayGroup> _groupByDay(List<TransactionEntry> transactions) {
    final Map<String, List<TransactionEntry>> grouped = {};
    for (final tx in transactions) {
      final key = DateFormat('yyyy-MM-dd').format(tx.timestamp);
      grouped.putIfAbsent(key, () => []).add(tx);
    }
    return grouped.entries
        .map((e) => _DayGroup(DateTime.parse(e.key), e.value))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // ── Edit category dialog ─────────────────────────────────────────────────

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
                    await (db.update(db.transactions)
                          ..where((t) => t.id.equals(tx.id)))
                        .write(TransactionsCompanion(
                            categoryId: drift.Value(selectedId)));

                    if (tx.counterparty != null &&
                        tx.counterparty!.isNotEmpty) {
                      await SmsIngestionService.learnCategoryRule(
                        db,
                        tx.counterparty!,
                        selectedId!,
                      );
                      await (db.update(db.transactions)
                            ..where((t) =>
                                t.counterparty.equals(tx.counterparty!)))
                          .write(TransactionsCompanion(
                              categoryId: drift.Value(selectedId)));
                    }

                    if (tx.type == 'expense') {
                      await db.analyticsDao
                          .checkBudgetThresholds(selectedId!, tx.timestamp);
                      await db.analyticsDao
                          .checkBudgetThresholds(selectedId!, DateTime.now());
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

  // ── Filter bottom sheet ──────────────────────────────────────────────────

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Filter Transactions',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    TextButton(
                      onPressed: () {
                        setState(() => _filters = _filters.reset());
                        setSheetState(() {});
                        Navigator.pop(context);
                      },
                      child: const Text('Reset all',
                          style: TextStyle(color: AppTheme.primaryPink)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Type',
                    style: TextStyle(
                        color: AppTheme.textDisabled, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _TypeFilter.values.map((f) {
                    final labels = {
                      _TypeFilter.all: 'All',
                      _TypeFilter.income: 'Income',
                      _TypeFilter.expense: 'Expense',
                      _TypeFilter.transfer: 'Transfer',
                    };
                    return ChoiceChip(
                      label: Text(labels[f]!),
                      selected: _filters.type == f,
                      onSelected: (_) {
                        setState(() =>
                            _filters = _filters.copyWith(type: f));
                        setSheetState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Payment Method',
                    style: TextStyle(
                        color: AppTheme.textDisabled, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _MethodFilter.values.map((f) {
                    final labels = {
                      _MethodFilter.all: 'All',
                      _MethodFilter.mpesa: 'M-Pesa',
                      _MethodFilter.cash: 'Cash',
                      _MethodFilter.card: 'Card',
                    };
                    return ChoiceChip(
                      label: Text(labels[f]!),
                      selected: _filters.method == f,
                      onSelected: (_) {
                        setState(() =>
                            _filters = _filters.copyWith(method: f));
                        setSheetState(() {});
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('Date Range',
                    style: TextStyle(
                        color: AppTheme.textDisabled, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _filters.date == _DateFilter.all,
                      onSelected: (_) {
                        setState(() => _filters = _filters.copyWith(
                            date: _DateFilter.all,
                            clearCustomRange: true));
                        setSheetState(() {});
                      },
                    ),
                    ChoiceChip(
                      label: const Text('This month'),
                      selected: _filters.date == _DateFilter.thisMonth,
                      onSelected: (_) {
                        setState(() => _filters = _filters.copyWith(
                            date: _DateFilter.thisMonth));
                        setSheetState(() {});
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Last 7 days'),
                      selected: _filters.date == _DateFilter.last7Days,
                      onSelected: (_) {
                        setState(() => _filters = _filters.copyWith(
                            date: _DateFilter.last7Days));
                        setSheetState(() {});
                      },
                    ),
                    ActionChip(
                      label: Text(_filters.date == _DateFilter.custom &&
                              _filters.customRange != null
                          ? '${DateFormat.MMMd().format(_filters.customRange!.start)} – ${DateFormat.MMMd().format(_filters.customRange!.end)}'
                          : 'Custom range'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year - 2),
                          lastDate: now,
                          initialDateRange: _filters.customRange,
                        );
                        if (picked != null) {
                          setState(() => _filters = _filters.copyWith(
                              date: _DateFilter.custom,
                              customRange: picked));
                          setSheetState(() {});
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Apply'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(dbProvider);
    final currencyFormatter =
        NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 2);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        title: _searchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                cursorColor: AppTheme.primaryPink,
                decoration: const InputDecoration(
                  hintText: 'Search by name or amount…',
                  hintStyle: TextStyle(color: AppTheme.textDisabled),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('M-Tracker'),
        actions: [
          // Search icon: toggles search field
          IconButton(
            icon: Icon(
              _searchActive ? Icons.close : Icons.search,
              color: _searchActive ? AppTheme.primaryPink : null,
            ),
            tooltip: _searchActive ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                _searchActive = !_searchActive;
                if (!_searchActive) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          // Filter icon: opens filter sheet
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Filter',
                onPressed: () => _showFilterSheet(context),
              ),
              if (_filters.isActive)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryPink,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<TransactionEntry>>(
        stream: _watchFilteredTransactions(db),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final filtered = snapshot.data ?? [];

          if (filtered.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.search_off,
                      color: AppTheme.textDisabled, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    (!(_searchQuery.isNotEmpty || _filters.type != _TypeFilter.all || _filters.method != _MethodFilter.all || _filters.date != _DateFilter.all) && filtered.isEmpty)
                        ? 'No transactions yet.\nAdd your first expense.'
                        : 'No results match your search or filters.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.textDisabled, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          // Active filter chips row
          final groups = _groupByDay(filtered);

          // Build flat list: [chips?] + for each group: [header, tx, tx, ...]
          final items = <_ListItem>[];
          for (final g in groups) {
            items.add(_HeaderItem(g.date, g.dailySpend));
            for (final tx in g.transactions) {
              items.add(_TxItem(tx));
            }
          }

          return Column(
            children: [
              // Active filter chip row
              if (_filters.isActive || _searchQuery.isNotEmpty)
                _ActiveFilterBar(
                  searchQuery: _searchQuery,
                  filters: _filters,
                  onClearSearch: () => setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                    _searchActive = false;
                  }),
                  onClearFilters: () =>
                      setState(() => _filters = _filters.reset()),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item is _HeaderItem) {
                      return _DayHeader(
                          date: item.date, dailySpend: item.dailySpend);
                    }
                    final tx = (item as _TxItem).tx;
                    return _TransactionRow(
                      tx: tx,
                      currencyFormatter: currencyFormatter,
                      db: db,
                      onEdit: () =>
                          _showEditCategoryDialog(context, tx, db),
                      onDelete: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Transaction'),
                            content: const Text(
                                'Are you sure you want to delete this transaction?'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, false),
                                child: const Text('Cancel',
                                    style: TextStyle(
                                        color: AppTheme.textSecondary)),
                              ),
                              ElevatedButton(
                                onPressed: () =>
                                    Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        AppTheme.semanticRed),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) {
                          await (db.delete(db.transactions)
                                ..where((t) => t.id.equals(tx.id)))
                              .go();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── List item types (sealed-ish via subclassing) ─────────────────────────────

abstract class _ListItem {}

class _HeaderItem extends _ListItem {
  final DateTime date;
  final double dailySpend;
  _HeaderItem(this.date, this.dailySpend);
}

class _TxItem extends _ListItem {
  final TransactionEntry tx;
  _TxItem(this.tx);
}

// ─── Day header widget ────────────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final DateTime date;
  final double dailySpend;

  const _DayHeader({required this.date, required this.dailySpend});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().format(date);
    final spendStr = NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 0)
        .format(dailySpend);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateStr,
                style: const TextStyle(
                  color: AppTheme.textDisabled,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (dailySpend > 0)
                Text(
                  '$spendStr spent',
                  style: const TextStyle(
                    color: AppTheme.semanticRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(color: Colors.white12, height: 1),
        ],
      ),
    );
  }
}

// ─── Transaction row widget ───────────────────────────────────────────────────

class _TransactionRow extends StatelessWidget {
  final TransactionEntry tx;
  final NumberFormat currencyFormatter;
  final AppDatabase db;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TransactionRow({
    required this.tx,
    required this.currencyFormatter,
    required this.db,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
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
    final dateFormatter = DateFormat.jm(); // time-only: day is already in header

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 2.0),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
          subtitle: Text(dateFormatter.format(tx.timestamp)),
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
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppTheme.textDisabled),
                onPressed: onDelete,
              ),
            ],
          ),
          onLongPress: onEdit,
          onTap: onEdit,
        ),
      ),
    );
  }
}

// ─── Active filter bar ────────────────────────────────────────────────────────

class _ActiveFilterBar extends StatelessWidget {
  final String searchQuery;
  final _FilterState filters;
  final VoidCallback onClearSearch;
  final VoidCallback onClearFilters;

  const _ActiveFilterBar({
    required this.searchQuery,
    required this.filters,
    required this.onClearSearch,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (searchQuery.isNotEmpty) {
      chips.add(_Chip(
        label: '"$searchQuery"',
        icon: Icons.search,
        onRemove: onClearSearch,
      ));
    }
    if (filters.type != _TypeFilter.all) {
      final labels = {
        _TypeFilter.income: 'Income',
        _TypeFilter.expense: 'Expense',
        _TypeFilter.transfer: 'Transfer',
      };
      chips.add(_Chip(
        label: labels[filters.type]!,
        icon: Icons.swap_vert,
        onRemove: onClearFilters,
      ));
    }
    if (filters.method != _MethodFilter.all) {
      final labels = {
        _MethodFilter.mpesa: 'M-Pesa',
        _MethodFilter.cash: 'Cash',
        _MethodFilter.card: 'Card',
      };
      chips.add(_Chip(
        label: labels[filters.method]!,
        icon: Icons.credit_card,
        onRemove: onClearFilters,
      ));
    }
    if (filters.date != _DateFilter.all) {
      String label;
      if (filters.date == _DateFilter.thisMonth) {
        label = 'This month';
      } else if (filters.date == _DateFilter.last7Days) {
        label = 'Last 7 days';
      } else {
        label = filters.customRange != null
            ? '${DateFormat.MMMd().format(filters.customRange!.start)}–${DateFormat.MMMd().format(filters.customRange!.end)}'
            : 'Custom';
      }
      chips.add(_Chip(
        label: label,
        icon: Icons.date_range,
        onRemove: onClearFilters,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(spacing: 8, children: chips),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onRemove;

  const _Chip(
      {required this.label, required this.icon, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: AppTheme.primaryPink),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      deleteIcon: const Icon(Icons.close, size: 14, color: AppTheme.textDisabled),
      onDeleted: onRemove,
      backgroundColor: AppTheme.primaryPink.withValues(alpha: 0.12),
      side: const BorderSide(color: AppTheme.primaryPink, width: 0.5),
      visualDensity: VisualDensity.compact,
    );
  }
}
