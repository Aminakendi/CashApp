import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// A curated, horizontally-scrollable icon picker for savings goals.
///
/// Renders 9 icon options. The [selected] icon gets a pink accent ring.
/// [onChanged] fires when the user taps a different icon.
/// Once [onChanged] has fired at least once, the parent should set
/// [_userHasPickedIcon] = true to stop the keyword auto-guess from
/// overriding the user's explicit choice.
class GoalIconPicker extends StatelessWidget {
  final IconData selected;
  final ValueChanged<IconData> onChanged;

  const GoalIconPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const List<_IconOption> options = [
    _IconOption(Icons.flight_takeoff, 'Vacation'),
    _IconOption(Icons.kitchen, 'Appliance'),
    _IconOption(Icons.checkroom, 'Clothes'),
    _IconOption(Icons.house, 'Home'),
    _IconOption(Icons.directions_car, 'Car'),
    _IconOption(Icons.card_giftcard, 'Gift'),
    _IconOption(Icons.phone_android, 'Phone'),
    _IconOption(Icons.school, 'Education'),
    _IconOption(Icons.flag, 'Other'),
  ];

  /// Returns the best-guess icon for [name] using keyword matching.
  /// Falls back to [Icons.flag] (not piggy bank) for unrecognised names.
  static IconData iconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('vacation') ||
        lower.contains('trip') ||
        lower.contains('travel') ||
        lower.contains('flight')) {
      return Icons.flight_takeoff;
    }
    if (lower.contains('fridge') ||
        lower.contains('appliance') ||
        lower.contains('tv')) {
      return Icons.kitchen;
    }
    if (lower.contains('clothes') ||
        lower.contains('fashion') ||
        lower.contains('outfit') ||
        lower.contains('wardrobe')) {
      return Icons.checkroom;
    }
    if (lower.contains('house') ||
        lower.contains('home') ||
        lower.contains('rent')) {
      return Icons.house;
    }
    if (lower.contains('car') ||
        lower.contains('vehicle') ||
        lower.contains('auto')) {
      return Icons.directions_car;
    }
    if (lower.contains('gift') || lower.contains('present')) {
      return Icons.card_giftcard;
    }
    if (lower.contains('phone') ||
        lower.contains('gadget') ||
        lower.contains('laptop') ||
        lower.contains('macbook')) {
      return Icons.phone_android;
    }
    if (lower.contains('school') ||
        lower.contains('education') ||
        lower.contains('tuition') ||
        lower.contains('fee')) {
      return Icons.school;
    }
    if (lower.contains('emergency') || lower.contains('fund')) {
      return Icons.health_and_safety;
    }
    return Icons.flag;
  }

  /// Serialises an [IconData] to a hex string for DB storage.
  static String iconToString(IconData icon) =>
      icon.codePoint.toRadixString(16);

  /// Deserialises a hex string back to an [IconData].
  static IconData iconFromString(String hex) =>
      IconData(int.parse(hex, radix: 16), fontFamily: 'MaterialIcons');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final opt = options[i];
          final isSelected = selected == opt.icon;
          return GestureDetector(
            onTap: () => onChanged(opt.icon),
            child: Tooltip(
              message: opt.label,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? AppTheme.primaryPink.withOpacity(0.15)
                      : Colors.white.withOpacity(0.05),
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primaryPink
                        : Colors.white24,
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                child: Icon(
                  opt.icon,
                  color: isSelected ? AppTheme.primaryPink : AppTheme.textDisabled,
                  size: 26,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IconOption {
  final IconData icon;
  final String label;
  const _IconOption(this.icon, this.label);
}
