import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/goals_provider.dart';
import '../../theme/app_theme.dart';
import '../../database/database.dart';
import 'goal_icon_picker.dart';

class CreateGoalSheet extends ConsumerStatefulWidget {
  final SavingsGoal? existingGoal;

  const CreateGoalSheet({super.key, this.existingGoal});

  @override
  ConsumerState<CreateGoalSheet> createState() => _CreateGoalSheetState();
}

class _CreateGoalSheetState extends ConsumerState<CreateGoalSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  DateTime? _selectedDate;
  String? _dateError;

  IconData _selectedIcon = Icons.flag;
  bool _userHasPickedIcon = false;

  @override
  void initState() {
    super.initState();
    
    if (widget.existingGoal != null) {
      final goal = widget.existingGoal!;
      _nameController.text = goal.name;
      _targetController.text = goal.targetAmount.toStringAsFixed(2).replaceAll(RegExp(r'\.00$'), '');
      _selectedDate = goal.targetDate;
      
      if (goal.iconName != null) {
        // ignore: non_const_argument_for_const_parameter
        _selectedIcon = IconData(int.parse(goal.iconName!, radix: 16), fontFamily: 'MaterialIcons');
        _userHasPickedIcon = true;
      } else {
        _selectedIcon = GoalIconPicker.iconForName(goal.name);
        _userHasPickedIcon = true; // Lock auto-guess for existing goals
      }
    } else {
      _selectedDate = DateTime.now();
    }

    _nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    // Only auto-update the icon if the user hasn't explicitly chosen one yet.
    if (!_userHasPickedIcon) {
      final guess = GoalIconPicker.iconForName(_nameController.text);
      if (guess != _selectedIcon) {
        setState(() => _selectedIcon = guess);
      }
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() {
      _dateError = null;
    });

    if (_selectedDate == null) {
      setState(() {
        _dateError = 'Please select a target date';
      });
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(
        _selectedDate!.year, _selectedDate!.month, _selectedDate!.day);

    // If editing and the date is unchanged, allow it to remain in the past.
    bool isUnchangedDate = false;
    if (widget.existingGoal != null) {
      final existingTarget = DateTime(
          widget.existingGoal!.targetDate.year,
          widget.existingGoal!.targetDate.month,
          widget.existingGoal!.targetDate.day);
      if (target.isAtSameMomentAs(existingTarget)) {
        isUnchangedDate = true;
      }
    }

    if (!isUnchangedDate && target.isBefore(today)) {
      setState(() {
        _dateError = 'Target date cannot be in the past';
      });
      return;
    }

    if (_formKey.currentState!.validate()) {
      final name = _nameController.text.trim();
      final targetAmount = double.parse(_targetController.text.trim());
      final iconName = GoalIconPicker.iconToString(_selectedIcon);

      if (widget.existingGoal != null) {
        ref.read(goalsNotifierProvider).updateGoal(
              widget.existingGoal!.id,
              name,
              targetAmount,
              _selectedDate!,
              iconName: iconName,
            );
      } else {
        ref.read(goalsNotifierProvider).createGoal(
              name,
              targetAmount,
              _selectedDate!,
              iconName: iconName,
            );
      }

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existingGoal != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEdit ? 'Edit Savings Goal' : 'Create Savings Goal',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Goal Name',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(color: Colors.white),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  if (value.trim().length > 50) {
                    return 'Name must be 50 characters or fewer';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                'Icon',
                style: TextStyle(color: AppTheme.textDisabled, fontSize: 13),
              ),
              const SizedBox(height: 8),
              GoalIconPicker(
                selected: _selectedIcon,
                onChanged: (icon) {
                  setState(() {
                    _selectedIcon = icon;
                    _userHasPickedIcon = true;
                  });
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _targetController,
                decoration: const InputDecoration(
                  labelText: 'Target Amount (KSh)',
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a target amount';
                  }
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Please enter a valid amount greater than 0';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _selectedDate == null
                      ? 'Select target date'
                      : DateFormat.yMMMd().format(_selectedDate!),
                  style: TextStyle(
                    color: _selectedDate == null
                        ? AppTheme.textDisabled
                        : Colors.white,
                  ),
                ),
                subtitle: _dateError != null
                    ? Text(
                        _dateError!,
                        style: const TextStyle(
                            color: AppTheme.semanticRed, fontSize: 12),
                      )
                    : null,
                trailing: const Icon(Icons.calendar_today,
                    color: AppTheme.primaryPink),
                onTap: () async {
                  final now = DateTime.now();
                  // For the date picker constraints: if the existing date is in the past,
                  // allow selecting dates from that past date onwards, or from today onwards.
                  final initialDate = _selectedDate ?? now;
                  final firstDate = initialDate.isBefore(now) ? initialDate : DateTime(now.year, now.month, now.day);
                  
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initialDate,
                    firstDate: firstDate,
                    lastDate: DateTime(now.year + 10),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                      _dateError = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryPink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(isEdit ? 'Save Changes' : 'Create Goal',
                    style:
                        const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

