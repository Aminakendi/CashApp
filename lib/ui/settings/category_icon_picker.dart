import 'package:flutter/material.dart';

class CategoryIconPicker extends StatelessWidget {
  const CategoryIconPicker({super.key});

  // A distinct, broader set of icons suitable for categorization
  static const List<IconData> categoryIcons = [
    Icons.shopping_cart,
    Icons.fastfood,
    Icons.local_cafe,
    Icons.restaurant,
    Icons.directions_car,
    Icons.local_gas_station,
    Icons.flight,
    Icons.home,
    Icons.water_drop,
    Icons.electric_bolt,
    Icons.wifi,
    Icons.phone_android,
    Icons.movie,
    Icons.sports_esports,
    Icons.fitness_center,
    Icons.medical_services,
    Icons.pets,
    Icons.school,
    Icons.menu_book,
    Icons.work,
    Icons.account_balance,
    Icons.attach_money,
    Icons.volunteer_activism,
    Icons.shopping_bag,
    Icons.checkroom,
    Icons.child_care,
    Icons.celebration,
    Icons.card_giftcard,
    Icons.spa,
    Icons.chair,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select an Icon',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: categoryIcons.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final iconData = categoryIcons[index];
                return InkWell(
                  onTap: () {
                    // Return the hex string of the codePoint
                    Navigator.pop(context, iconData.codePoint.toRadixString(16));
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconData, size: 32),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
