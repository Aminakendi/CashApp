import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers/db_provider.dart';
import '../services/sms_sync_manager.dart';
import '../services/sync_state_service.dart';

class PermissionOnboardingSheet extends ConsumerStatefulWidget {
  final VoidCallback onCompleted;

  const PermissionOnboardingSheet({
    super.key,
    required this.onCompleted,
  });

  static Future<void> showIfNeeded(BuildContext context, VoidCallback onCompleted) async {
    final hasSmsPermission = await Permission.sms.isGranted;
    final historicalDone = await SyncStateService.isHistoricalSyncDone();

    if (!hasSmsPermission && !historicalDone && context.mounted) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (ctx) => PermissionOnboardingSheet(onCompleted: onCompleted),
      );
    }
  }

  @override
  ConsumerState<PermissionOnboardingSheet> createState() => _PermissionOnboardingSheetState();
}

class _PermissionOnboardingSheetState extends ConsumerState<PermissionOnboardingSheet> {
  bool _isSyncing = false;
  String _syncStatusText = '';
  int _currentProgress = 0;
  int _totalMessages = 0;

  Future<void> _handleEnableTracking() async {
    final status = await Permission.sms.request();

    if (status.isGranted) {
      setState(() {
        _isSyncing = true;
        _syncStatusText = 'Scanning M-Pesa SMS messages...';
      });

      final db = ref.read(dbProvider);

      // Initialize background capture & periodic tasks
      await SmsSyncManager.initialize(db);

      // Perform one-time historical sync
      await SmsSyncManager.performHistoricalSync(
        db,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _currentProgress = current;
              _totalMessages = total;
              _syncStatusText = total > 0
                  ? 'Importing M-Pesa history ($current / $total)...'
                  : 'Importing M-Pesa history...';
            });
          }
        },
      );

      setState(() {
        _isSyncing = false;
      });

      // Prompt for Battery Optimization exemption
      if (mounted) {
        await _showBatteryOptimizationPrompt();
      }

      widget.onCompleted();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'SMS permission was not granted. You can still add expenses manually or enable SMS anytime in Settings.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        widget.onCompleted();
      }
    }
  }

  Future<void> _showBatteryOptimizationPrompt() async {
    final isAlreadyExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    if (isAlreadyExempt) return;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.battery_charging_full, color: Color(0xFF10B981)),
            SizedBox(width: 10),
            Text('Reliable Background Capture', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'To ensure incoming M-Pesa receipts are captured even when the app is swiped away or closed, please allow battery optimization exemption.\n\n'
          'This is especially critical for Tecno, Infinix, and Xiaomi devices with aggressive background app killers.',
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Maybe Later', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await Permission.ignoreBatteryOptimizations.request();
            },
            child: const Text('Allow Exemption'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mark_email_read_outlined,
                color: Color(0xFF10B981),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Automatic M-Pesa Tracking',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Grant SMS permission to automatically track your M-Pesa expenses, receipts, and balances in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Color(0xFF10B981), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '100% Private & Offline: Your SMS messages are parsed locally on your device and never uploaded to any server.',
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            if (_isSyncing) ...[
              LinearProgressIndicator(
                value: _totalMessages > 0 ? (_currentProgress / _totalMessages) : null,
                backgroundColor: const Color(0xFF1E293B),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
              ),
              const SizedBox(height: 12),
              Text(
                _syncStatusText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
            ] else ...[
              ElevatedButton(
                onPressed: _handleEnableTracking,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Enable Automatic Tracking',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onCompleted();
                },
                child: const Text(
                  'Continue with Manual Entry Only',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
