import 'package:drift/drift.dart';

@DataClassName('TransactionEntry')
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  RealColumn get amount => real()();
  TextColumn get type => text()(); // income, expense, transfer
  TextColumn get source => text()(); // mpesa_sms, manual
  TextColumn get mpesaTransactionCode => text().nullable().unique()();
  TextColumn get mpesaSubtype => text().nullable()(); // send, receive, buyGoods, etc.
  TextColumn get counterparty => text().nullable()();
  IntColumn get categoryId => integer().nullable().references(Categories, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get notes2 => text().nullable()(); // Added for v2 migration testing
  TextColumn get paymentMethod => text()(); // mpesa, cash, card
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get rawSmsText => text().nullable()();
}

@DataClassName('Category')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  RealColumn get monthlyBudget => real().nullable()();
}

@DataClassName('SavingsGoal')
class SavingsGoals extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  RealColumn get targetAmount => real()();
  RealColumn get currentAmount => real().withDefault(const Constant(0.0))();
  DateTimeColumn get targetDate => dateTime()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('CategoryRule')
class CategoryRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get pattern => text()();
  IntColumn get categoryId => integer().references(Categories, #id)();
}

@DataClassName('UnparsedMessage')
class UnparsedMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get rawSms => text()();
  TextColumn get reason => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
