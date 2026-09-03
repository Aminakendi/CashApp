import 'package:shared_preferences/shared_preferences.dart';

class SyncStateService {
  static const _keyLastSyncedAt = 'mpesa_tracker_last_synced_at';
  static const _keyHistoricalSyncDone = 'mpesa_tracker_historical_sync_done';
  static const _keyBatteryPromptShown = 'mpesa_tracker_battery_prompt_shown';

  static Future<DateTime?> getLastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final epochMs = prefs.getInt(_keyLastSyncedAt);
    if (epochMs == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(epochMs);
  }

  static Future<void> setLastSyncedAt(DateTime timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncedAt, timestamp.millisecondsSinceEpoch);
  }

  static Future<bool> isHistoricalSyncDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHistoricalSyncDone) ?? false;
  }

  static Future<void> setHistoricalSyncDone(bool done) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHistoricalSyncDone, done);
  }

  static Future<bool> isBatteryPromptShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBatteryPromptShown) ?? false;
  }

  static Future<void> setBatteryPromptShown(bool shown) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBatteryPromptShown, shown);
  }
}
