import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'theme/app_theme.dart';
import 'providers/db_provider.dart';
import 'database/seeder.dart';
import 'services/sms_sync_manager.dart';
import 'ui/dashboard_screen.dart';
import 'ui/permission_onboarding_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _isSeeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isSeeded) {
      final db = ref.read(dbProvider);
      // Layer 3: Differential sync on resume from background
      SmsSyncManager.performDifferentialSync(db);
    }
  }

  Future<void> _initialize() async {
    final db = ref.read(dbProvider);
    await DatabaseSeeder.seedCategoriesIfEmpty(db);

    final hasSmsPermission = await Permission.sms.isGranted;
    if (hasSmsPermission) {
      await SmsSyncManager.initialize(db);
    }

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M-Pesa Tracker',
      theme: AppTheme.darkTheme,
      home: _isSeeded
          ? const DashboardScreen()
          : const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
    );
  }
}
