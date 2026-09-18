import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/goals_provider.dart';
import '../../theme/app_theme.dart';
import '../../database/database.dart';
import '../widgets/goal_card.dart';
import 'create_goal_sheet.dart';

class GoalDetailScreen extends ConsumerWidget {
  final int goalId;

  const GoalDetailScreen({super.key, required this.goalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalAsyncValue = ref.watch(goalProvider(goalId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Goal Details'),
        elevation: 0,
        actions: goalAsyncValue.value == null
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.edit, color: AppTheme.textSecondary),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: AppTheme.surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      builder: (ctx) => CreateGoalSheet(
                        existingGoal: goalAsyncValue.value!,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.semanticRed),
                  onPressed: () => _showDeleteConfirmation(
                      context, ref, goalAsyncValue.value!),
                ),
              ],
      ),
      body: goalAsyncValue.when(
        data: (goal) {
          if (goal == null) {
            return const Center(
              child: Text(
                'Goal not found',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 16),
                GoalCard(
                  goal: goal,
                  onTap: () {}, // Already here, do nothing
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddContributionDialog(context, ref, goal.name),
                    icon: const Icon(Icons.add),
                    label: const Text('Log Contribution'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryPink,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryPink),
        ),
        error: (err, stack) => Center(
          child: Text(
            'Error: $err',
            style: const TextStyle(color: AppTheme.semanticRed),
          ),
        ),
      ),
    );
  }

  void _showAddContributionDialog(BuildContext context, WidgetRef ref, String goalName) {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: Text(
            'Add to $goalName',
            style: const TextStyle(color: Colors.white),
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Amount (KSh)',
                labelStyle: const TextStyle(color: AppTheme.textSecondary),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.textDisabled),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryPink),
                ),
              ),
              validator: (val) {
                if (val == null || val.isEmpty) return 'Please enter an amount';
                final parsed = double.tryParse(val);
                if (parsed == null || parsed <= 0) return 'Must be greater than 0';
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  final amount = double.parse(controller.text);
                  await ref.read(goalsNotifierProvider).addContribution(goalId, amount);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryPink,
              ),
              child: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref, SavingsGoal goal) {
    showDialog(
      context: context,
      builder: (ctx) {
        final savedFormatted = NumberFormat('#,##0').format(goal.currentAmount);
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
            'Delete Goal?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            "Delete '${goal.name}'? You've saved Ksh $savedFormatted toward this goal — this cannot be undone.",
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                await ref.read(goalsNotifierProvider).deleteGoal(goal.id);
                if (ctx.mounted) {
                  Navigator.pop(ctx); // Close dialog
                  Navigator.pop(context); // Close detail screen
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.semanticRed,
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
}
