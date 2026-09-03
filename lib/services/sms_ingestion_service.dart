import 'package:drift/drift.dart' as drift;
import '../database/database.dart';
import '../parser/mpesa_parser.dart';

class IngestionResult {
  final bool isParsed;
  final bool isDuplicate;
  final ParsedTransaction? parsed;
  final UnparsedTransaction? unparsed;

  IngestionResult.success(this.parsed, {this.isDuplicate = false})
      : isParsed = true,
        unparsed = null;

  IngestionResult.unparsed(this.unparsed)
      : isParsed = false,
        isDuplicate = false,
        parsed = null;
}

class SmsIngestionService {
  /// Ingests a single SMS message into the database.
  /// Deduplicates silently using the `mpesaTransactionCode` unique constraint.
  /// Routes unparsed transactions to the `UnparsedMessages` table.
  static Future<IngestionResult> processSingleSms(
    AppDatabase db,
    String rawSms, {
    DateTime? fallbackTimestamp,
  }) async {
    final parseResult = MpesaParser.parse(rawSms);

    if (parseResult is ParsedTransaction) {
      // Check if this transaction code is already recorded
      final existing = await (db.select(db.transactions)
            ..where((t) => t.mpesaTransactionCode.equals(parseResult.transactionCode)))
          .getSingleOrNull();

      if (existing != null) {
        return IngestionResult.success(parseResult, isDuplicate: true);
      }

      final categoryId = await _resolveCategoryId(db, parseResult);

      await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
          amount: parseResult.amount,
          type: parseResult.type.name,
          source: 'mpesa_sms',
          mpesaTransactionCode: drift.Value(parseResult.transactionCode),
          mpesaSubtype: drift.Value(parseResult.subtype.name),
          counterparty: drift.Value(parseResult.counterparty),
          categoryId: drift.Value(categoryId),
          paymentMethod: 'mpesa',
          timestamp: parseResult.timestamp,
          rawSmsText: drift.Value(parseResult.rawSms),
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );

      return IngestionResult.success(parseResult, isDuplicate: false);
    } else if (parseResult is UnparsedTransaction) {
      // Record unparsed SMS for user review
      await db.into(db.unparsedMessages).insert(
        UnparsedMessagesCompanion.insert(
          rawSms: parseResult.rawSms,
          reason: parseResult.reason,
        ),
        mode: drift.InsertMode.insertOrIgnore,
      );

      return IngestionResult.unparsed(parseResult);
    }

    return IngestionResult.unparsed(
      UnparsedTransaction(rawSms, 'Unknown parse outcome'),
    );
  }

  /// Ingests a list of SMS messages in a single database transaction for high performance.
  static Future<int> processBatchSms(
    AppDatabase db,
    List<String> rawSmsList,
  ) async {
    int insertedCount = 0;

    await db.transaction(() async {
      for (final rawSms in rawSmsList) {
        final result = await processSingleSms(db, rawSms);
        if (result.isParsed && !result.isDuplicate) {
          insertedCount++;
        }
      }
    });

    return insertedCount;
  }

  /// Automatically matches a category based on rules, subtypes, or merchant keywords.
  static Future<int?> _resolveCategoryId(
    AppDatabase db,
    ParsedTransaction tx,
  ) async {
    try {
      final rules = await db.select(db.categoryRules).get();
      final counterpartyUpper = tx.counterparty?.toUpperCase() ?? '';

      // 1. Check custom user rules
      for (final rule in rules) {
        if (counterpartyUpper.contains(rule.pattern.toUpperCase())) {
          return rule.categoryId;
        }
      }

      // 2. Fetch seeded categories to map by name
      final categories = await db.select(db.categories).get();
      final categoryMap = {for (var c in categories) c.name.toLowerCase(): c.id};

      // Helper to find category by any matching prefix/keyword
      int? findCat(List<String> candidates) {
        for (final cand in candidates) {
          for (final entry in categoryMap.entries) {
            if (entry.key.contains(cand.toLowerCase())) {
              return entry.value;
            }
          }
        }
        return null;
      }

      // 3. Subtype-based categorization
      if (tx.subtype == MpesaSubtype.airtime) {
        return findCat(['airtime', 'utilities']);
      }
      if (tx.subtype == MpesaSubtype.fuliza) {
        return findCat(['fuliza', 'debt']);
      }
      if (tx.subtype == MpesaSubtype.mshwari || tx.subtype == MpesaSubtype.kcb) {
        return findCat(['savings', 'investment', 'other']);
      }

      // 4. Keyword heuristic matching
      if (counterpartyUpper.contains('NAIVAS') ||
          counterpartyUpper.contains('CARREFOUR') ||
          counterpartyUpper.contains('QUICKMART') ||
          counterpartyUpper.contains('CHANDARANA') ||
          counterpartyUpper.contains('CLEANSHELF') ||
          counterpartyUpper.contains('SUPERMARKET') ||
          counterpartyUpper.contains('MART')) {
        return findCat(['shopping', 'food']);
      }

      if (counterpartyUpper.contains('KPLC') ||
          counterpartyUpper.contains('KENYA POWER') ||
          counterpartyUpper.contains('ZUKU') ||
          counterpartyUpper.contains('SAFARICOM HOME') ||
          counterpartyUpper.contains('NAIROBI WATER') ||
          counterpartyUpper.contains('WATER')) {
        return findCat(['utilities', 'bills']);
      }

      if (counterpartyUpper.contains('UBER') ||
          counterpartyUpper.contains('BOLT') ||
          counterpartyUpper.contains('LITTLE') ||
          counterpartyUpper.contains('TOTAL') ||
          counterpartyUpper.contains('RUBIS') ||
          counterpartyUpper.contains('SHELL') ||
          counterpartyUpper.contains('PETROL') ||
          counterpartyUpper.contains('MATATU')) {
        return findCat(['transport']);
      }

      if (counterpartyUpper.contains('KFC') ||
          counterpartyUpper.contains('JAVA') ||
          counterpartyUpper.contains('ARTCAFFE') ||
          counterpartyUpper.contains('DOMINOS') ||
          counterpartyUpper.contains('PIZZA INN') ||
          counterpartyUpper.contains('RESTAURANT') ||
          counterpartyUpper.contains('CAFE') ||
          counterpartyUpper.contains('FOOD')) {
        return findCat(['food']);
      }

      return categoryMap['other'];
    } catch (_) {
      return null;
    }
  }
}
