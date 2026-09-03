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
      final categories = await db.select(db.categories).get();
      final categoryMap = {for (var c in categories) c.name.toLowerCase(): c.id};
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

      // 1. Check text-based rules using counterparty
      final textBasedCategory = await resolveCategoryForText(db, tx.counterparty ?? '');
      if (textBasedCategory != null) {
        return textBasedCategory;
      }

      // 2. Subtype-based categorization
      if (tx.subtype == MpesaSubtype.airtime) {
        return findCat(['airtime', 'utilities']);
      }
      if (tx.subtype == MpesaSubtype.fuliza) {
        return findCat(['fuliza', 'debt']);
      }
      if (tx.subtype == MpesaSubtype.mshwari || tx.subtype == MpesaSubtype.kcb) {
        return findCat(['savings', 'investment', 'other']);
      }

      return categoryMap['other'];
    } catch (_) {
      return null;
    }
  }

  /// Exposed for manual entry screens to auto-suggest categories based on text input.
  static Future<int?> resolveCategoryForText(
    AppDatabase db,
    String text,
  ) async {
    if (text.isEmpty) return null;
    try {
      final rules = await db.select(db.categoryRules).get();
      final textUpper = text.toUpperCase();

      for (final rule in rules) {
        if (textUpper.contains(rule.pattern.toUpperCase())) {
          return rule.categoryId;
        }
      }

      final categories = await db.select(db.categories).get();
      final categoryMap = {for (var c in categories) c.name.toLowerCase(): c.id};

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

      if (textUpper.contains('NAIVAS') ||
          textUpper.contains('CARREFOUR') ||
          textUpper.contains('QUICKMART') ||
          textUpper.contains('CHANDARANA') ||
          textUpper.contains('CLEANSHELF') ||
          textUpper.contains('SUPERMARKET') ||
          textUpper.contains('MART')) {
        return findCat(['shopping', 'food']);
      }

      if (textUpper.contains('KPLC') ||
          textUpper.contains('KENYA POWER') ||
          textUpper.contains('ZUKU') ||
          textUpper.contains('SAFARICOM HOME') ||
          textUpper.contains('NAIROBI WATER') ||
          textUpper.contains('WATER')) {
        return findCat(['utilities', 'bills']);
      }

      if (textUpper.contains('UBER') ||
          textUpper.contains('BOLT') ||
          textUpper.contains('LITTLE') ||
          textUpper.contains('TOTAL') ||
          textUpper.contains('RUBIS') ||
          textUpper.contains('SHELL') ||
          textUpper.contains('PETROL') ||
          textUpper.contains('MATATU')) {
        return findCat(['transport']);
      }

      if (textUpper.contains('KFC') ||
          textUpper.contains('JAVA') ||
          textUpper.contains('ARTCAFFE') ||
          textUpper.contains('DOMINOS') ||
          textUpper.contains('PIZZA INN') ||
          textUpper.contains('RESTAURANT') ||
          textUpper.contains('CAFE') ||
          textUpper.contains('FOOD')) {
        return findCat(['food']);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  /// Records a new CategoryRule when a user manually categorizes a transaction,
  /// so the app learns this mapping for future auto-suggestions.
  static Future<void> learnCategoryRule(
    AppDatabase db,
    String counterparty,
    int categoryId,
  ) async {
    if (counterparty.isEmpty) return;
    
    // Convert to upper case for consistency
    final pattern = counterparty.toUpperCase();
    
    // Check if a rule already exists for this exact pattern
    final existing = await (db.select(db.categoryRules)
          ..where((r) => r.pattern.equals(pattern)))
        .getSingleOrNull();
        
    if (existing != null) {
      if (existing.categoryId != categoryId) {
        // Update existing rule if the category changed
        await db.update(db.categoryRules).replace(
          existing.copyWith(categoryId: categoryId),
        );
      }
    } else {
      // Insert new rule
      await db.into(db.categoryRules).insert(
        CategoryRulesCompanion.insert(
          pattern: pattern,
          categoryId: categoryId,
        ),
      );
    }
  }
}
