import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../database/database.dart';
import '../../theme/app_theme.dart';
import '../goals/goal_icon_picker.dart';

class GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final VoidCallback onTap;

  const GoalCard({
    super.key,
    required this.goal,
    required this.onTap,
  });

  IconData _resolveIcon() {
    // User's explicit pick (persisted as hex codePoint) always wins.
    final stored = goal.iconName;
    if (stored != null && stored.isNotEmpty) {
      return GoalIconPicker.iconFromString(stored);
    }
    // Fall back to keyword guess for goals created before v5 (iconName == null).
    return GoalIconPicker.iconForName(goal.name);
  }

  String _getTimeRemaining(DateTime? targetDate) {
    if (targetDate == null) return 'No date set';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target =
        DateTime(targetDate.year, targetDate.month, targetDate.day);

    if (target.isBefore(today)) {
      return 'Overdue';
    } else if (target.isAtSameMomentAs(today)) {
      return 'Due today';
    }

    final days = target.difference(today).inDays;
    if (days < 60) {
      return '$days days left';
    } else {
      final months = (days / 30).floor();
      return '$months months left';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat =
        NumberFormat.currency(symbol: 'KSh ', decimalDigits: 0);

    final currentAmount = goal.currentAmount;
    final targetAmount = goal.targetAmount;
    final trueProgress = targetAmount > 0 ? (currentAmount / targetAmount) : 0.0;
    final displayProgress = trueProgress.clamp(0.0, 1.0);
    final remaining = targetAmount - currentAmount;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryPink.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _resolveIcon(),
                      color: AppTheme.primaryPink,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goal.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _getTimeRemaining(goal.targetDate),
                          style: const TextStyle(
                            color: AppTheme.textDisabled,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${(trueProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: AppTheme.primaryPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: displayProgress,
                backgroundColor: Colors.white12,
                color: AppTheme.primaryPink,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Saved',
                        style: TextStyle(
                          color: AppTheme.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        currencyFormat.format(currentAmount),
                        style: const TextStyle(
                          color: AppTheme.primaryPink,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Target',
                        style: TextStyle(
                          color: AppTheme.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        currencyFormat.format(targetAmount),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (remaining > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${currencyFormat.format(remaining)} remaining',
                    style: const TextStyle(
                      color: AppTheme.textDisabled,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
