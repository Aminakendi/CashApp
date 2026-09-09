import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/db_provider.dart';
import '../../theme/app_theme.dart';
import '../../database/database.dart';

class AnalyticsTab extends ConsumerStatefulWidget {
  const AnalyticsTab({super.key});

  @override
  ConsumerState<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends ConsumerState<AnalyticsTab> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(dbProvider);
    final currencyFormatter = NumberFormat.currency(symbol: 'Ksh ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Analytics'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: FutureBuilder(
        future: Future.wait([
          db.analyticsDao.getTotalIncome(_currentMonth.year, _currentMonth.month),
          db.analyticsDao.getTotalExpenses(_currentMonth.year, _currentMonth.month),
          db.analyticsDao.getCategorySpend(_currentMonth.year, _currentMonth.month),
          db.analyticsDao.getWastedSpendCandidates(_currentMonth.year, _currentMonth.month),
          db.analyticsDao.getFulizaStats(_currentMonth.year, _currentMonth.month),
          db.select(db.categories).get(), // Need categories for icons
        ]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
          }

          final data = snapshot.data as List<dynamic>;
          final totalIncome = data[0] as double;
          final totalExpenses = data[1] as double;
          final categorySpend = data[2] as List<dynamic>; // List<CategorySpend>
          final wastedSpend = data[3] as List<dynamic>; // List<WastedSpend>
          final fulizaStats = data[4] as Map<String, double>;
          final categories = data[5] as List<Category>;

          final net = totalIncome - totalExpenses;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMonthSelector(),
                const SizedBox(height: 24),
                _buildSummaryCards(totalIncome, totalExpenses, net, currencyFormatter),
                const SizedBox(height: 24),
                if (totalExpenses > 0) ...[
                  const Text('Category Breakdown', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildDonutChart(categorySpend, totalExpenses),
                  const SizedBox(height: 16),
                  _buildCategoryList(categorySpend, categories, currencyFormatter),
                  const SizedBox(height: 32),
                ],
                if (wastedSpend.isNotEmpty) ...[
                  const Text('Wasted Spend Candidates', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Small, frequent purchases that add up.', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                  const SizedBox(height: 16),
                  _buildWastedSpend(wastedSpend, currencyFormatter),
                  const SizedBox(height: 32),
                ],
                if (fulizaStats['usage']! > 0 || fulizaStats['repayment']! > 0) ...[
                  const Text('Fuliza Usage', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _buildFulizaCard(fulizaStats, currencyFormatter),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMonthSelector() {
    final monthFormat = DateFormat('MMMM yyyy');
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: _previousMonth,
        ),
        Text(
          monthFormat.format(_currentMonth),
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, color: Colors.white),
          onPressed: () {
            final now = DateTime.now();
            if (_currentMonth.year < now.year || (_currentMonth.year == now.year && _currentMonth.month < now.month)) {
              _nextMonth();
            }
          },
        ),
      ],
    );
  }

  Widget _buildSummaryCards(double income, double expense, double net, NumberFormat formatter) {
    return Row(
      children: [
        Expanded(child: _buildCard('Income', formatter.format(income), AppTheme.semanticGreen)),
        const SizedBox(width: 8),
        Expanded(child: _buildCard('Expenses', formatter.format(expense), AppTheme.semanticRed)),
        const SizedBox(width: 8),
        Expanded(child: _buildCard('Net', formatter.format(net), net >= 0 ? AppTheme.semanticGreen : AppTheme.semanticRed)),
      ],
    );
  }

  Widget _buildCard(String title, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 8),
          Text(amount, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  final List<Color> _chartColors = [
    const Color(0xFF6366F1), // Indigo
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF59E0B), // Amber
    const Color(0xFFEF4444), // Red
    const Color(0xFF8B5CF6), // Violet
    const Color(0xFF06B6D4), // Cyan
    const Color(0xFFF43F5E), // Rose
  ];

  Widget _buildDonutChart(List<dynamic> categorySpend, double totalExpenses) {
    if (categorySpend.isEmpty) return const SizedBox.shrink();

    final sections = <PieChartSectionData>[];
    for (int i = 0; i < categorySpend.length; i++) {
      final spend = categorySpend[i];
      final color = _chartColors[i % _chartColors.length];
      final percentage = (spend.totalSpend / totalExpenses) * 100;
      
      sections.add(
        PieChartSectionData(
          color: color,
          value: spend.totalSpend,
          title: '${percentage.toStringAsFixed(0)}%',
          radius: 50,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: PieChart(
        PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 60,
          sections: sections,
        ),
      ),
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

  Widget _buildCategoryList(List<dynamic> categorySpend, List<Category> categories, NumberFormat formatter) {
    return Column(
      children: List.generate(categorySpend.length, (index) {
        final spend = categorySpend[index];
        final color = _chartColors[index % _chartColors.length];
        
        String iconName = 'category';
        if (spend.categoryId != null) {
          try {
            final cat = categories.firstWhere((c) => c.id == spend.categoryId);
            iconName = cat.icon;
          } catch (_) {}
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.2),
                  child: Icon(_getIconForName(iconName), color: color, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    spend.categoryName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  formatter.format(spend.totalSpend),
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildWastedSpend(List<dynamic> wastedSpend, NumberFormat formatter) {
    return Column(
      children: wastedSpend.map((w) {
        return Card(
          color: AppTheme.surface,
          child: ListTile(
            leading: const Icon(Icons.warning_amber_rounded, color: AppTheme.semanticRed),
            title: Text(w.counterparty, style: const TextStyle(color: Colors.white)),
            subtitle: Text('${w.count} transactions', style: const TextStyle(color: AppTheme.textSecondary)),
            trailing: Text(formatter.format(w.totalSpend), style: const TextStyle(color: AppTheme.semanticRed, fontWeight: FontWeight.bold)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFulizaCard(Map<String, double> stats, NumberFormat formatter) {
    final net = stats['usage']! - stats['repayment']!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: net > 0 ? AppTheme.semanticRed.withValues(alpha: 0.3) : AppTheme.semanticGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Used this month', style: TextStyle(color: AppTheme.textSecondary)),
              Text(formatter.format(stats['usage']), style: const TextStyle(color: AppTheme.semanticRed, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Repaid this month', style: TextStyle(color: AppTheme.textSecondary)),
              Text(formatter.format(stats['repayment']), style: const TextStyle(color: AppTheme.semanticGreen, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(height: 24, color: AppTheme.textDisabled),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(net > 0 ? 'Outstanding addition' : 'Net reduction', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text(formatter.format(net.abs()), style: TextStyle(color: net > 0 ? AppTheme.semanticRed : AppTheme.semanticGreen, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
