import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';
import 'package:mpesa_tracker/services/backup_service.dart';
import 'package:mpesa_tracker/services/sync_state_service.dart';
import 'package:mpesa_tracker/ui/settings/category_management_screen.dart';
import 'package:mpesa_tracker/ui/settings/notification_history_screen.dart';
import 'package:mpesa_tracker/ui/settings/security_settings_screen.dart';
import 'package:mpesa_tracker/providers/app_lock_provider.dart';
import 'package:mpesa_tracker/services/app_lock_service.dart';
import 'package:mpesa_tracker/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<DateTime?> _syncFuture;

  @override
  void initState() {
    super.initState();
    _syncFuture = _getSyncTime();
  }

  Future<DateTime?> _getSyncTime() async {
    final status = await Permission.sms.status;
    if (!status.isGranted) return null;
    return await SyncStateService.getLastSyncedAt();
  }

  String _formatRelativeTime(DateTime? timestamp) {
    if (timestamp == null) return 'Not synced yet';
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} hr ago';
    return '${diff.inDays} days ago';
  }

  String _formatTimeout(int seconds) {
    if (seconds == 0) return 'Immediately';
    if (seconds == 30) return '30s';
    if (seconds == 60) return '1m';
    if (seconds == 300) return '5m';
    return '${seconds}s';
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildIcon(IconData icon, {bool isWarning = false}) {
    final color = isWarning ? AppTheme.semanticAmber : AppTheme.primaryPink;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.read(dbProvider);
    final unreadStream = (db.select(db.appNotifications)..where((n) => n.isRead.equals(false))).watch();
    final categoriesStream = db.select(db.categories).watch();
    final lockService = ref.watch(appLockProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: StreamBuilder(
        stream: unreadStream,
        builder: (context, unreadSnapshot) {
          final unreadCount = unreadSnapshot.data?.length ?? 0;

          return StreamBuilder(
            stream: categoriesStream,
            builder: (context, categoriesSnapshot) {
              final defaultCount = categoriesSnapshot.data?.where((c) => c.id < 1000).length ?? 0;
              final customCount = categoriesSnapshot.data?.where((c) => c.id >= 1000).length ?? 0;

              return ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  // Header Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'M-Tracker',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Track your M-Pesa transactions at a glance',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                        const SizedBox(height: 16),
                        FutureBuilder<DateTime?>(
                          future: _syncFuture,
                          builder: (context, syncSnapshot) {
                            return StreamBuilder<int>(
                              stream: db.customSelect('SELECT COUNT(*) AS c FROM transactions').watchSingle().map((row) => row.read<int>('c')),
                              builder: (context, txSnapshot) {
                                final count = txSnapshot.data ?? 0;
                                final syncStr = _formatRelativeTime(syncSnapshot.data);
                                final txStr = count == 1 ? '1 transaction' : '$count transactions';
                                return Text(
                                  '$txStr · Last synced $syncStr',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  _buildSectionHeader('General'),
                  _buildCard([
                    ListTile(
                      leading: _buildIcon(Icons.category),
                      title: const Text('Manage Categories'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add, edit, or delete custom categories'),
                          const SizedBox(height: 4),
                          Text('$defaultCount default · $customCount custom', 
                            style: const TextStyle(color: AppTheme.primaryPink, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagementScreen()));
                      },
                    ),
                    const Divider(height: 1, indent: 72, color: AppTheme.surfaceBorder),
                    ListTile(
                      leading: _buildIcon(Icons.notifications_outlined),
                      title: const Text('Notifications'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('View history of budget alerts'),
                          if (unreadCount > 0) ...[
                            const SizedBox(height: 4),
                            Text('$unreadCount unread', style: const TextStyle(color: AppTheme.primaryPink, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]
                        ]
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationHistoryScreen()));
                      },
                    ),
                  ]),

                  _buildSectionHeader('Security & Data'),
                  _buildCard([
                    ListTile(
                      leading: _buildIcon(Icons.security),
                      title: const Text('Security'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('App Lock and biometrics'),
                          const SizedBox(height: 4),
                          Text(
                            lockService.isEnabled ? 'On · ${_formatTimeout(lockService.timeoutSecs)}' : 'Off',
                            style: const TextStyle(color: AppTheme.primaryPink, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()));
                      },
                    ),
                    const Divider(height: 1, indent: 72, color: AppTheme.surfaceBorder),
                    ListTile(
                      leading: _buildIcon(Icons.download, isWarning: true),
                      title: const Text('Export Data (JSON)'),
                      subtitle: const Text('Save an unencrypted backup of all your data'),
                      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
                      onTap: () async {
                        if (lockService.isEnabled) {
                          final authResult = await lockService.authenticate(reason: 'Authenticate to export data');
                          if (authResult != AuthResult.success) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Authentication required to export data.')),
                              );
                            }
                            return;
                          }
                        }
                        if (!context.mounted) return;
                        
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
                                child: const Text('EXPORT', style: TextStyle(color: AppTheme.semanticRed)),
                              ),
                            ],
                          ),
                        );
                        
                        if (confirmed == true) {
                          lockService.setSystemAction(true);
                          try {
                            final dbInstance = ref.read(dbProvider);
                            await BackupService.exportDataToJson(dbInstance);
                          } finally {
                            lockService.setSystemAction(false);
                          }
                        }
                      },
                    ),
                  ]),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
