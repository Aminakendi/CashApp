import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:io';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // For iOS (if needed in the future)
    const DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);

    if (Platform.isAndroid) {
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  Future<void> showBudgetAlert(String categoryName, double percentage, double spent, double budget) async {
    final int percentInt = (percentage * 100).toInt();
    final String title = 'Budget Alert: $categoryName';
    String body;
    
    if (percentInt >= 100) {
      body = 'You have exceeded your budget for $categoryName. Spent: Ksh $spent / Budget: Ksh $budget.';
    } else {
      body = 'You have reached $percentInt% of your budget for $categoryName. Spent: Ksh $spent / Budget: Ksh $budget.';
    }

    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'budget_alerts_channel',
      'Budget Alerts',
      channelDescription: 'Notifications for when you approach or exceed your category budgets.',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    final int notificationId = categoryName.hashCode + percentInt;
    
    await flutterLocalNotificationsPlugin.show(
      notificationId % 100000, 
      title,
      body,
      platformChannelSpecifics,
    );
  }
}
