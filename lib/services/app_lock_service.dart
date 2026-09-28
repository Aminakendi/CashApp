import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthResult { success, failed, lockRemoved }

class AppLockService extends ChangeNotifier {
  static final AppLockService _instance = AppLockService._internal();
  factory AppLockService() => _instance;
  
  final LocalAuthentication _auth = LocalAuthentication();
  late SharedPreferences _prefs;

  bool _isLocked = false;
  bool _isEnabled = false;
  int _timeoutSecs = 60; // default 1 minute
  
  bool _isAuthenticating = false;
  bool _isSystemAction = false;
  
  DateTime? _lastBackgroundTime;

  AppLockService._internal();

  bool get isLocked => _isLocked;
  bool get isEnabled => _isEnabled;
  int get timeoutSecs => _timeoutSecs;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _isEnabled = _prefs.getBool('app_lock_enabled') ?? false;
    _timeoutSecs = _prefs.getInt('app_lock_timeout_secs') ?? 60;
    
    if (_isEnabled) {
      _isLocked = true;
    }
  }

  void setSystemAction(bool isSystemAction) {
    _isSystemAction = isSystemAction;
  }

  Future<AuthResult> authenticate({String reason = 'Unlock M-Tracker'}) async {
    if (_isAuthenticating) return AuthResult.failed;
    
    _isAuthenticating = true;
    try {
      final canAuthenticate = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuthenticate) {
        // Device lock removed!
        _isLocked = false;
        _isEnabled = false;
        await _prefs.setBool('app_lock_enabled', false);
        notifyListeners();
        return AuthResult.lockRemoved;
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (didAuthenticate) {
        _isLocked = false;
        notifyListeners();
        return AuthResult.success;
      }
      return AuthResult.failed;
    } catch (e) {
      return AuthResult.failed;
    } finally {
      _isAuthenticating = false;
    }
  }

  Future<bool> toggleLock(bool enable) async {
    final canAuthenticate = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    if (enable && !canAuthenticate) {
      return false; // Cannot enable if not supported
    }

    final result = await authenticate(reason: enable ? 'Authenticate to enable App Lock' : 'Authenticate to disable App Lock');
    if (result == AuthResult.success || result == AuthResult.lockRemoved) {
      _isEnabled = enable;
      await _prefs.setBool('app_lock_enabled', enable);
      if (!enable) {
        _isLocked = false;
      }
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> setTimeout(int seconds) async {
    _timeoutSecs = seconds;
    await _prefs.setInt('app_lock_timeout_secs', seconds);
    notifyListeners();
  }

  void onLifecyclePaused() {
    if (_isAuthenticating || _isSystemAction) return;
    _lastBackgroundTime = DateTime.now();
  }

  void onLifecycleResumed() {
    if (_isAuthenticating || _isSystemAction) return;
    
    if (_isEnabled && _lastBackgroundTime != null) {
      final elapsed = DateTime.now().difference(_lastBackgroundTime!).inSeconds;
      if (elapsed >= _timeoutSecs) {
        _isLocked = true;
        notifyListeners();
      }
    }
    _lastBackgroundTime = null;
  }
}
