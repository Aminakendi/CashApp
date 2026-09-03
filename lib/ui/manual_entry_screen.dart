import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/db_provider.dart';
import '../database/database.dart';
import 'package:drift/drift.dart' as drift;
import '../services/sms_ingestion_service.dart';

class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _noteController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  String _paymentMethod = 'cash';
  int? _selectedCategoryId;
  List<Category> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _counterpartyController.addListener(_onCounterpartyChanged);
  }

  @override
  void dispose() {
    _counterpartyController.dispose();
    _noteController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _onCounterpartyChanged() async {
    final text = _counterpartyController.text;
    if (text.length > 2) {
      final db = ref.read(dbProvider);
      final suggestedId = await SmsIngestionService.resolveCategoryForText(db, text);
      if (suggestedId != null && mounted && _selectedCategoryId != suggestedId) {
        setState(() {
          _selectedCategoryId = suggestedId;
        });
      }
    }
  }

  Future<void> _loadCategories() async {
    final db = ref.read(dbProvider);
    final categories = await db.select(db.categories).get();
    setState(() {
      _categories = categories;
      if (_categories.isNotEmpty) {
        _selectedCategoryId = _categories.first.id;
      }
    });
  }

  Future<void> _saveTransaction() async {
    final amountText = _amountController.text.replaceAll(',', '');
    final amount = double.tryParse(amountText);
    
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }

    final db = ref.read(dbProvider);
    final counterparty = _counterpartyController.text.trim();
    
    await db.into(db.transactions).insert(
      TransactionsCompanion.insert(
        amount: amount,
        type: 'expense',
        source: 'manual',
        categoryId: drift.Value(_selectedCategoryId),
        counterparty: drift.Value(counterparty.isEmpty ? null : counterparty),
        note: drift.Value(_noteController.text.isEmpty ? null : _noteController.text),
        paymentMethod: _paymentMethod,
        timestamp: _selectedDate,
      ),
    );

    if (counterparty.isNotEmpty && _selectedCategoryId != null) {
      await SmsIngestionService.learnCategoryRule(db, counterparty, _selectedCategoryId!);
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _categories.isEmpty 
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: ListView(
                children: [
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'Ksh ',
                    ),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories.map((cat) {
                      return DropdownMenuItem<int>(
                        value: cat.id,
                        child: Text(cat.name),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedCategoryId = val),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'card', child: Text('Card')),
                      DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa (Manual)')),
                    ],
                    onChanged: (val) => setState(() => _paymentMethod = val!),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _counterpartyController,
                    decoration: const InputDecoration(
                      labelText: 'Payee / Merchant',
                      hintText: 'e.g. Uber, Naivas',
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _noteController,
                    decoration: const InputDecoration(labelText: 'Note (Optional)'),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    title: const Text('Date'),
                    subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
                    trailing: const Icon(Icons.calendar_today),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: Theme.of(context).inputDecorationTheme.fillColor,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: _saveTransaction,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Save Expense', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
    );
  }
}
