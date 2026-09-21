import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';
import 'package:mpesa_tracker/services/backup_service.dart';
import 'package:mpesa_tracker/ui/settings/category_management_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Export Data (JSON)'),
            subtitle: const Text('Save an unencrypted backup of all your data'),
            onTap: () async {
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
                final dbInstance = ref.read(dbProvider);
                await BackupService.exportDataToJson(dbInstance);
              }
            },
          ),
        ],
      ),
    );
  }
}
