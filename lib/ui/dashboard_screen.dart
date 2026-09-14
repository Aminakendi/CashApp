import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/db_provider.dart';
import '../database/seeder.dart';
import '../theme/app_theme.dart';
import 'manual_entry_screen.dart';
import 'permission_onboarding_dialog.dart';
import '../services/notification_service.dart';
import '../services/sms_sync_manager.dart';
import '../services/backup_service.dart';

import 'tabs/home_tab.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/budget_tab.dart';
import 'tabs/goals_tab.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isSeeded = false;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final db = ref.read(dbProvider);
    await DatabaseSeeder.seedCategoriesIfEmpty(db);

    // Seed known counterparty→category rules (one-time, guard: runs only if
    // CategoryRules table is empty). Survives future launches safely.
    await DatabaseSeeder.seedCategoryRulesIfEmpty(db);

    // Retroactively re-apply rules to any expense transactions currently
    // sitting at the wrong category (e.g., "Other" after a data wipe).
    final reclassified =
        await DatabaseSeeder.reapplyCategoryRulesToExistingTransactions(db);
    if (reclassified > 0) {
      debugPrint('>>> SEEDER: Reclassified $reclassified existing transactions <<<');
    }



    // Request notification permission from the UI — after the app has rendered.
    // Must NOT be called from main() as it shows an OS dialog that blocks runApp().
    await NotificationService().requestPermissionIfNeeded();

    final hasSmsPermission = await Permission.sms.isGranted;
    if (hasSmsPermission) {
      await SmsSyncManager.initialize(db);
      await SmsSyncManager.reprocessUnparsedMessages(db);
    }

    if (mounted) {
      setState(() {
        _isSeeded = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          PermissionOnboardingSheet.showIfNeeded(context, () {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('M-Pesa Tracker'),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings_outlined),
            onSelected: (value) async {
              if (value == 'export') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Export Data'),
                    content: const Text(
                        'This will export your transactions, categories, savings goals, and budget settings to a JSON file.\n\nWARNING: The exported file is UNENCRYPTED and contains sensitive financial data. Keep it safe.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('CANCEL'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('EXPORT', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  final db = ref.read(dbProvider);
                  // Use BackupService to export data
                  await BackupService.exportDataToJson(db);
                }
              } else if (value == 'settings') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings coming soon')),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Export Data (JSON)'),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: Text('Settings'),
              ),
            ],
          ),
        ],
      ),
      body: !_isSeeded 
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _currentIndex,
              children: const [
                HomeTab(),
                AnalyticsTab(),
                BudgetTab(),
                GoalsTab(),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppTheme.surface,
        selectedItemColor: AppTheme.primaryPink,
        unselectedItemColor: AppTheme.textDisabled,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.insights),
            label: 'Analytics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'Budget',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.track_changes),
            label: 'Goals',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0 ? FloatingActionButton.extended(
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
      ) : null,
    );
  }
}
