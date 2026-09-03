import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:mpesa_tracker/database/seeder.dart';
import 'package:mpesa_tracker/services/sms_ingestion_service.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    // Use an in-memory native database for testing
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await DatabaseSeeder.seedCategoriesIfEmpty(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('Multi-Layer Dedup: Simulate Layer 1, Layer 2, and Layer 3 capturing same SMS', () async {
    const sms =
        'QA12BC3456 Confirmed. Ksh2,500.00 sent to JANE DOE 0722000000 on 12/03/24 at 4:15 PM. New M-PESA balance is Ksh15,400.00. Transaction cost, Ksh34.00.';

    // Simulate Layer 1: Instant Background Listener captures SMS
    final result1 = await SmsIngestionService.processSingleSms(database, sms);
    expect(result1.isParsed, true);
    expect(result1.isDuplicate, false);
    expect(result1.parsed?.transactionCode, 'QA12BC3456');

    var allTx = await database.select(database.transactions).get();
    expect(allTx.length, 1);
    expect(allTx.first.mpesaTransactionCode, 'QA12BC3456');
    expect(allTx.first.amount, 2500.0);

    // Simulate Layer 2: WorkManager periodic sync runs 10 mins later and encounters same SMS
    final result2 = await SmsIngestionService.processSingleSms(database, sms);
    expect(result2.isParsed, true);
    expect(result2.isDuplicate, true, reason: 'Layer 2 should silently recognize duplicate');

    // Confirm no errors and row count is still 1
    allTx = await database.select(database.transactions).get();
    expect(allTx.length, 1);

    // Simulate Layer 3: App launch differential sync triggers and encounters same SMS
    final result3 = await SmsIngestionService.processSingleSms(database, sms);
    expect(result3.isParsed, true);
    expect(result3.isDuplicate, true, reason: 'Layer 3 should silently recognize duplicate');

    allTx = await database.select(database.transactions).get();
    expect(allTx.length, 1);
  });

  test('Batch Historical Sync: Ingests multiple SMS in a single fast transaction', () async {
    final batchSms = [
      'TXN0000001 Confirmed. Ksh500.00 paid to NAIVAS SUPERMARKET on 01/01/24 at 10:00 AM. New M-PESA balance is Ksh5,000.00.',
      'TXN0000002 Confirmed. Ksh1,200.00 paid to KPLC PREPAID on 02/01/24 at 11:30 AM. New M-PESA balance is Ksh3,800.00.',
      'TXN0000003 Confirmed. You have received Ksh3,000.00 from PETER PAN on 03/01/24 at 2:15 PM. New M-PESA balance is Ksh6,800.00.',
      'TXN0000001 Confirmed. Ksh500.00 paid to NAIVAS SUPERMARKET on 01/01/24 at 10:00 AM. New M-PESA balance is Ksh5,000.00.', // Duplicate in batch
    ];

    final insertedCount = await SmsIngestionService.processBatchSms(database, batchSms);
    expect(insertedCount, 3, reason: 'Only 3 unique transactions should be inserted');

    final allTx = await database.select(database.transactions).get();
    expect(allTx.length, 3);
  });

  test('Auto-Categorization: Maps merchant keywords to seeded categories', () async {
    const naivasSms =
        'TXN0000004 Confirmed. Ksh850.00 paid to NAIVAS WESTLANDS on 05/01/24 at 1:00 PM. New M-PESA balance is Ksh2,000.00.';
    const kplcSms =
        'TXN0000005 Confirmed. Ksh1,000.00 sent to KPLC PREPAID for account 123456 on 06/01/24 at 3:00 PM. New M-PESA balance is Ksh1,000.00.';

    await SmsIngestionService.processSingleSms(database, naivasSms);
    await SmsIngestionService.processSingleSms(database, kplcSms);

    final txList = await database.select(database.transactions).get();
    final naivasTx = txList.firstWhere((t) => t.mpesaTransactionCode == 'TXN0000004');
    final kplcTx = txList.firstWhere((t) => t.mpesaTransactionCode == 'TXN0000005');

    expect(naivasTx.categoryId, isNotNull);
    expect(kplcTx.categoryId, isNotNull);

    final categories = await database.select(database.categories).get();
    final naivasCat = categories.firstWhere((c) => c.id == naivasTx.categoryId);
    final kplcCat = categories.firstWhere((c) => c.id == kplcTx.categoryId);

    expect(naivasCat.name.toLowerCase(), contains('shopping'));
    expect(kplcCat.name.toLowerCase(), contains('utilities'));
  });

  test('Unparsed Messages: Routes non-transaction SMS to UnparsedMessages table', () async {
    const promoSms = 'Safaricom offers: Get 1GB for Ksh 50. Dial *544#';

    final result = await SmsIngestionService.processSingleSms(database, promoSms);
    expect(result.isParsed, false);
    expect(result.unparsed?.reason, 'Missing Confirmed keyword');

    final unparsedList = await database.select(database.unparsedMessages).get();
    expect(unparsedList.length, 1);
    expect(unparsedList.first.rawSms, promoSms);
    expect(unparsedList.first.reason, 'Missing Confirmed keyword');
  });
}
