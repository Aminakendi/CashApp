import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mpesa_tracker/providers/db_provider.dart';
import 'package:mpesa_tracker/database/database.dart';

class NotificationHistoryScreen extends ConsumerWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(dbProvider);
    final notificationStream = db.watchNotifications();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'mark_all_read') {
                await db.markAllNotificationsAsRead();
              } else if (value == 'clear_history') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear History'),
                    content: const Text('Are you sure you want to delete all notification history?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('CANCEL'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await db.clearNotificationHistory();
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'mark_all_read',
                child: Text('Mark all as read'),
              ),
              const PopupMenuItem(
                value: 'clear_history',
                child: Text('Clear history'),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder(
        stream: notificationStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final notifications = snapshot.data ?? [];
          if (notifications.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          // Group by day
          final grouped = <String, List<dynamic>>{};
          final now = DateTime.now();
          final todayStr = DateFormat('yyyy-MM-dd').format(now);
          final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

          for (final n in notifications) {
            final date = DateTime.fromMillisecondsSinceEpoch(n.createdAt * 1000);
            final dateStr = DateFormat('yyyy-MM-dd').format(date);
            
            String groupKey;
            if (dateStr == todayStr) {
              groupKey = 'Today';
            } else if (dateStr == yesterdayStr) {
              groupKey = 'Yesterday';
            } else {
              groupKey = DateFormat('MMMM d, yyyy').format(date);
            }

            grouped.putIfAbsent(groupKey, () => []).add(n);
          }

          return ListView.builder(
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final groupKey = grouped.keys.elementAt(index);
              final items = grouped[groupKey]!;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      groupKey,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  ...items.map((n) {
                    final date = DateTime.fromMillisecondsSinceEpoch(n.createdAt * 1000);
                    final timeStr = DateFormat('HH:mm').format(date);
                    return ListTile(
                      leading: Icon(
                        Icons.notifications_outlined,
                        color: n.isRead ? Colors.grey : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        n.title,
                        style: TextStyle(
                          fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(n.body),
                          const SizedBox(height: 4),
                          Text(
                            timeStr,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          ),
                        ],
                      ),
                      trailing: n.isRead
                          ? null
                          : Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                      onTap: () async {
                        if (!n.isRead) {
                          await db.markNotificationAsRead(n.id);
                        }
                        if (context.mounted) {
                          Navigator.popUntil(context, (route) => route.isFirst);
                        }
                      },
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
