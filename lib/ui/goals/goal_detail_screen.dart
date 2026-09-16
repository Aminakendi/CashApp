import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/goals_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/goal_card.dart';

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
}
