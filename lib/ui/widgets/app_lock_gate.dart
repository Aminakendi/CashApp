import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/app_lock_provider.dart';
import '../../services/app_lock_service.dart';

class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLock();
    });
  }

  void _checkLock() async {
    final lockService = ref.read(appLockProvider);
    if (lockService.isLocked) {
      final result = await lockService.authenticate();
      if (result == AuthResult.lockRemoved) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device lock was removed. App Lock has been disabled.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockService = ref.watch(appLockProvider);
    
    if (lockService.isLocked) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('App Locked', style: TextStyle(fontSize: 24)),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _checkLock,
                child: const Text('Unlock'),
              ),
            ],
          ),
        ),
      );
    }

    return widget.child;
  }
}
