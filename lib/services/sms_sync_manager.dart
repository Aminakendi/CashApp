import 'dart:developer' as developer;
import 'package:flutter/widgets.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart' as inbox;
import 'package:telephony/telephony.dart' as tel;
import 'package:workmanager/workmanager.dart';

import '../database/database.dart';
import 'sms_ingestion_service.dart';
import 'sms_staging_service.dart';
import 'sync_state_service.dart';

/// Top-level background message handler for telephony (Layer 1).
/// Must be top-level and annotated with @pragma('vm:entry-point') so Flutter AOT doesn't tree-shake it.
@pragma('vm:entry-point')
void mpesaBackgroundMessageHandler(tel.SmsMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
  } catch (e) {
    developer.log('Layer 1 Init Error (MissingPluginException likely): $e', name: 'SmsSyncManager');
    return;
  }
  developer.log('Layer 1 Background SMS received: ${message.body}', name: 'SmsSyncManager');

  final body = message.body;
  if (body == null || body.isEmpty) return;

  try {
    await SmsStagingService.queueMessage(body);
    developer.log('Successfully queued SMS in staging', name: 'SmsSyncManager');
  } catch (e, stack) {
    developer.log('Error queueing background SMS: $e', name: 'SmsSyncManager', error: e, stackTrace: stack);
  }
}

/// Top-level WorkManager callback dispatcher for periodic sync (Layer 2).
/// Must be top-level and annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
void mpesaWorkmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    developer.log('Layer 2 WorkManager executing task: $taskName', name: 'SmsSyncManager');

    if (taskName == SmsSyncManager.periodicTaskName) {
      AppDatabase? db;
      bool success = false;
      try {
        db = AppDatabase();
        await SmsSyncManager.performDifferentialSync(db);
        success = true;
      } catch (e, stack) {
        developer.log('Error in WorkManager sync task: $e', name: 'SmsSyncManager', error: e, stackTrace: stack);
        success = false;
      } finally {
        await db?.close();
      }
      return success;
    }
    return true;
  });
}

class SmsSyncManager {
  static const String periodicTaskId = 'mpesa_periodic_sync_task_id';
  static const String periodicTaskName = 'mpesa_periodic_sync_task';

  /// Initializes the 3 sync layers.
  static Future<void> initialize(AppDatabase db) async {
    // 1. Initialize WorkManager (Layer 2)
    try {
      await Workmanager().initialize(
        mpesaWorkmanagerCallbackDispatcher,
        isInDebugMode: false,
      );

      await Workmanager().registerPeriodicTask(
        periodicTaskId,
        periodicTaskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
        ),
      );
      developer.log('WorkManager periodic sync registered (15 min interval)', name: 'SmsSyncManager');
    } catch (e) {
      developer.log('WorkManager init warning: $e', name: 'SmsSyncManager');
    }

    // 2. Initialize Telephony SMS Listener (Layer 1)
    try {
      final telephony = tel.Telephony.instance;
      telephony.listenIncomingSms(
        onNewMessage: (tel.SmsMessage message) async {
          final body = message.body;
          if (body != null && body.isNotEmpty) {
            await SmsIngestionService.processSingleSms(db, body);
            await SyncStateService.setLastSyncedAt(DateTime.now());
          }
        },
        onBackgroundMessage: mpesaBackgroundMessageHandler,
        listenInBackground: true,
      );
      developer.log('Telephony background listener activated', name: 'SmsSyncManager');
    } catch (e) {
      developer.log('Telephony listener registration warning: $e', name: 'SmsSyncManager');
    }

    // 3. Perform initial differential sync on launch (Layer 3)
    await performDifferentialSync(db);
  }

  /// Layer 3 & Layer 2 shared engine: Differential sync from SMS inbox.
  /// Queries messages newer than lastSyncedAt minus a 5-minute safety margin.
  static Future<int> performDifferentialSync(AppDatabase db) async {
    try {
      // 1. Drain the background staging queue first
      final stagedMessages = await SmsStagingService.drainQueue();
      if (stagedMessages.isNotEmpty) {
        developer.log('Draining ${stagedMessages.length} messages from staging queue', name: 'SmsSyncManager');
        final contents = stagedMessages.map((m) => m.content).toList();
        
        // This throws if DB insert completely fails.
        await SmsIngestionService.processBatchSms(db, contents);
        
        // ONLY if the batch succeeded, delete the files
        await SmsStagingService.deleteStagedFiles(stagedMessages);
      }

      final lastSyncedAt = await SyncStateService.getLastSyncedAt();
      final query = inbox.SmsQuery();

      // Query inbox SMS
      final allMessages = await query.querySms(
        kinds: [inbox.SmsQueryKind.inbox],
      );

      // Filter M-PESA related messages
      final mpesaMessages = allMessages.where((msg) {
        final address = (msg.address ?? '').toUpperCase();
        final body = msg.body ?? '';
        return address.contains('MPESA') ||
            address.contains('M-PESA') ||
            body.contains('Confirmed.');
      }).toList();

      if (mpesaMessages.isEmpty) {
        await SyncStateService.setLastSyncedAt(DateTime.now());
        return 0;
      }

      // If lastSyncedAt is known, apply differential filter
      final DateTime filterThreshold = lastSyncedAt != null
          ? lastSyncedAt.subtract(const Duration(minutes: 5))
          : DateTime.now().subtract(const Duration(days: 30));

      final newMessages = mpesaMessages.where((msg) {
        final date = msg.date;
        if (date == null) return true;
        return date.isAfter(filterThreshold);
      }).map((m) => m.body ?? '').where((b) => b.isNotEmpty).toList();

      if (newMessages.isNotEmpty) {
        final inserted = await SmsIngestionService.processBatchSms(db, newMessages);
        developer.log('Differential sync processed ${newMessages.length} SMS ($inserted new transactions)', name: 'SmsSyncManager');
      }

      await SyncStateService.setLastSyncedAt(DateTime.now());
      return newMessages.length;
    } catch (e, stack) {
      developer.log('Differential sync error: $e', name: 'SmsSyncManager', error: e, stackTrace: stack);
      return 0;
    }
  }

  /// First-run full historical sync.
  /// Scans inbox, imports all M-Pesa messages in a single fast DB transaction.
  static Future<int> performHistoricalSync(
    AppDatabase db, {
    void Function(int processed, int total)? onProgress,
  }) async {
    try {
      final query = inbox.SmsQuery();
      final allMessages = await query.querySms(
        kinds: [inbox.SmsQueryKind.inbox],
      );

      // Filter M-PESA messages
      final mpesaMessages = allMessages.where((msg) {
        final address = (msg.address ?? '').toUpperCase();
        final body = msg.body ?? '';
        return address.contains('MPESA') ||
            address.contains('M-PESA') ||
            body.contains('Confirmed.');
      }).map((m) => m.body ?? '').where((b) => b.isNotEmpty).toList();

      final total = mpesaMessages.length;
      if (total == 0) {
        await SyncStateService.setHistoricalSyncDone(true);
        await SyncStateService.setLastSyncedAt(DateTime.now());
        return 0;
      }

      onProgress?.call(0, total);

      // Ingest in a single DB transaction
      final insertedCount = await SmsIngestionService.processBatchSms(db, mpesaMessages);

      await SyncStateService.setHistoricalSyncDone(true);
      await SyncStateService.setLastSyncedAt(DateTime.now());
      onProgress?.call(total, total);

      developer.log('Historical sync complete: $insertedCount of $total messages saved', name: 'SmsSyncManager');
      return insertedCount;
    } catch (e, stack) {
      developer.log('Historical sync error: $e', name: 'SmsSyncManager', error: e, stackTrace: stack);
      return 0;
    }
  }
}
