import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';
import 'package:mpesa_tracker/services/backup_service.dart';
import 'package:mpesa_tracker/ui/settings/category_management_screen.dart';
import 'package:mpesa_tracker/ui/settings/notification_history_screen.dart';
import 'package:mpesa_tracker/ui/settings/security_settings_screen.dart';
import 'package:mpesa_tracker/providers/app_lock_provider.dart';
import 'package:mpesa_tracker/services/app_lock_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final unreadStream = (db.select(db.appNotifications)
          ..where((n) => n.isRead.equals(false)))
        .watch();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Manage Categories'),
            subtitle: const Text('Add, edit, or delete custom categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoryManagementScreen()),
              );
            },
          ),
          const Divider(),
          StreamBuilder(
            stream: unreadStream,
            builder: (context, snapshot) {
              final unreadCount = snapshot.data?.length ?? 0;
              return ListTile(
                leading: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 12,
                            minHeight: 12,
                          ),
                          child: Text(
                            '$unreadCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                title: const Text('Notifications'),
                subtitle: const Text('View history of budget alerts'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationHistoryScreen()),
                  );
                },
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Security'),
            subtitle: const Text('App Lock and biometrics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SecuritySettingsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export Data (JSON)'),
            subtitle: const Text('Save an unencrypted backup of all your data'),
            onTap: () async {
              final lockService = ref.read(appLockProvider);
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
                      child: const Text('EXPORT', style: TextStyle(color: Colors.red)),
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
        ],
      ),
    );
  }
}
