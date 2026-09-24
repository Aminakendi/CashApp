import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'theme/app_theme.dart';
import 'providers/db_provider.dart';

import 'services/sms_sync_manager.dart';
import 'services/notification_service.dart';
import 'ui/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await NotificationService().initializePlugin();

  // Workaround for older Android versions using sqlite3_flutter_libs
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  }

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final db = ref.read(dbProvider);
      // Layer 3: Differential sync on resume from background
      SmsSyncManager.performDifferentialSync(db);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M-Tracker',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const DashboardScreen(),
    );
  }
}
