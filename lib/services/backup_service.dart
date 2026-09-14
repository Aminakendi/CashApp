import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../database/database.dart';

class BackupService {
  /// Exports all core application data to a JSON file and prompts the user to
  /// share/save it via the OS share sheet.
  /// 
  /// Excludes UnparsedMessages as they are not core user data.
  static Future<void> exportDataToJson(AppDatabase db) async {
    final transactions = await db.select(db.transactions).get();
    final categories = await db.select(db.categories).get();
    final categoryRules = await db.select(db.categoryRules).get();
    final savingsGoals = await db.select(db.savingsGoals).get();
    final budgetNotifications = await db.select(db.budgetNotifications).get();

    final data = {
      'transactions': transactions.map((t) => t.toJson()).toList(),
      'categories': categories.map((c) => c.toJson()).toList(),
      'categoryRules': categoryRules.map((r) => r.toJson()).toList(),
      'savingsGoals': savingsGoals.map((g) => g.toJson()).toList(),
      'budgetNotifications': budgetNotifications.map((b) => b.toJson()).toList(),
    };

    final jsonString = jsonEncode(data);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${tempDir.path}/cashapp_export_$timestamp.json');
    
    await file.writeAsString(jsonString);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'CashApp Data Export (Unencrypted)',
    );
  }
}
