import 'package:flutter/material.dart';
import 'package:mpesa_tracker/ui/settings/category_icon_resolver.dart';

class CategoryIconPicker extends StatefulWidget {
  const CategoryIconPicker({super.key});

  @override
  State<CategoryIconPicker> createState() => _CategoryIconPickerState();
}

class _CategoryIconPickerState extends State<CategoryIconPicker> {
  final TextEditingController _searchController = TextEditingController();
  List<MapEntry<String, IconData>> _filteredIcons = [];
  
  final List<MapEntry<String, IconData>> _allIcons = 
      CategoryIconResolver.iconMap.entries.toList();

  @override
  void initState() {
    super.initState();
    _filteredIcons = _allIcons;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterIcons(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredIcons = _allIcons;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredIcons = _allIcons.where((entry) {
          final iconName = entry.key;
          // Match against the exact icon name first
          if (iconName.toLowerCase().contains(lowerQuery)) return true;
          // Then match against the keywords
          final keywords = CategoryIconResolver.keywordMap[iconName] ?? [];
          return keywords.any((k) => k.toLowerCase().contains(lowerQuery));
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: 16.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Select an Icon',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search icons (e.g. gym, food)',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: _filterIcons,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              itemCount: _filteredIcons.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemBuilder: (context, index) {
                final entry = _filteredIcons[index];
                return InkWell(
                  onTap: () {
                    // Return the string name of the icon
                    Navigator.pop(context, entry.key);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(entry.value, size: 32),
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
