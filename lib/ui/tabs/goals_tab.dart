import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/goals_provider.dart';
import '../../theme/app_theme.dart';
import '../widgets/goal_card.dart';
import '../goals/create_goal_sheet.dart';
import '../goals/goal_detail_screen.dart';

class GoalsTab extends ConsumerWidget {
  const GoalsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsyncValue = ref.watch(savingsGoalsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: goalsAsyncValue.when(
        data: (goals) {
          if (goals.isEmpty) {
            return const Center(
              child: Text(
                'No savings goals yet.\nTap + to create one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textDisabled, fontSize: 16),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80, top: 16),
            itemCount: goals.length,
            itemBuilder: (context, index) {
              final goal = goals[index];
              return GoalCard(
                goal: goal,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GoalDetailScreen(goalId: goal.id),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppTheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (context) => const CreateGoalSheet(),
          );
        },
        backgroundColor: AppTheme.primaryPink,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
