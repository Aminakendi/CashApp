import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_lock_provider.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lockService = ref.watch(appLockProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('App Lock'),
            subtitle: const Text('Require authentication to open the app'),
            value: lockService.isEnabled,
            onChanged: (value) async {
              final success = await lockService.toggleLock(value);
              if (value && !success) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not enable App Lock. Please ensure your device has a screen lock or biometrics set up.'),
                    ),
                  );
                }
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Lock after'),
            enabled: lockService.isEnabled,
            trailing: DropdownButton<int>(
              value: lockService.timeoutSecs,
              onChanged: lockService.isEnabled
                  ? (value) {
                      if (value != null) lockService.setTimeout(value);
                    }
                  : null,
              items: const [
                DropdownMenuItem(value: 0, child: Text('Immediately')),
                DropdownMenuItem(value: 30, child: Text('30 seconds')),
                DropdownMenuItem(value: 60, child: Text('1 minute')),
                DropdownMenuItem(value: 300, child: Text('5 minutes')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
