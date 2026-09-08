enum TransactionType { income, expense, transfer }
enum MpesaSubtype {
  send,
  receive,
  buyGoods,
  paybill,
  withdraw,
  airtime,
  fuliza,
  mshwari,
  kcb,
  reversal,
  unknown
}

sealed class ParseResult {}

class ParsedTransaction extends ParseResult {
  final String transactionCode;
  final TransactionType type;
  final MpesaSubtype subtype;
  final double amount;
  final String? counterparty;
  final double balance;
  final DateTime timestamp;
  final String rawSms;

  ParsedTransaction({
    required this.transactionCode,
    required this.type,
    required this.subtype,
    required this.amount,
    this.counterparty,
    required this.balance,
    required this.timestamp,
    required this.rawSms,
  });

  @override
  String toString() {
    return 'ParsedTransaction(code: $transactionCode, type: $type, subtype: $subtype, amount: $amount, counterparty: $counterparty, balance: $balance, timestamp: $timestamp)';
  }
}

class UnparsedTransaction extends ParseResult {
  final String rawSms;
  final String reason;

  UnparsedTransaction(this.rawSms, this.reason);
  
  @override
  String toString() => 'UnparsedTransaction(reason: $reason, sms: $rawSms)';
}

class MpesaParser {
  static final RegExp _codeRegExp = RegExp(r'^([A-Z0-9]{10})\s*confirmed\.', caseSensitive: false);
  static final RegExp _amountRegExp = RegExp(r'(?:confirmed\.|received|withdraw|bought|transaction of|pm\.|am\.)\s*ksh\s*([\d,]+\.\d{2})', caseSensitive: false);
  static final RegExp _balanceRegExp = RegExp(r'(?:new\s+)?m-pesa balance is\s*ksh\s*([\d,]+\.\d{2})', caseSensitive: false);
  static final RegExp _dateRegExp = RegExp(r'on\s+(\d{1,2}/\d{1,2}/\d{2,4})\s+at\s+(\d{1,2}:\d{2}\s*[APM]{2})', caseSensitive: false);

  static ParseResult parse(String sms) {
    final lowerSms = sms.toLowerCase();

    if (lowerSms.contains('failed.') || lowerSms.contains('failed,')) {
      return UnparsedTransaction(sms, 'Failed transaction');
    }
    
    if (!lowerSms.contains('confirmed.')) {
      return UnparsedTransaction(sms, 'Missing confirmed. keyword');
    }

    final codeMatch = _codeRegExp.firstMatch(sms);
    if (codeMatch == null) {
      return UnparsedTransaction(sms, 'Could not extract transaction code');
    }
    final code = codeMatch.group(1)!.toUpperCase();

    MpesaSubtype subtype = MpesaSubtype.unknown;
    TransactionType type = TransactionType.expense;
    String? counterparty;

    if (lowerSms.contains('reversal of transaction')) {
      subtype = MpesaSubtype.reversal;
      type = TransactionType.transfer;
    } else if (lowerSms.contains('you have received')) {
      subtype = MpesaSubtype.receive;
      type = TransactionType.income;
      final match = RegExp(r'from\s+(.*?)(?:\s+on|\.|\s*$)', caseSensitive: false).firstMatch(sms);
      counterparty = match?.group(1)?.trim();
    } else if (lowerSms.contains('sent to')) {
      if (lowerSms.contains('for account')) {
        subtype = MpesaSubtype.paybill;
        final match = RegExp(r'sent to\s+(.*?)\s+for account', caseSensitive: false).firstMatch(sms);
        counterparty = match?.group(1)?.trim();
      } else {
        subtype = MpesaSubtype.send;
        final match = RegExp(r'sent to\s+(.*?)(?:\s+on|\.|\s*$)', caseSensitive: false).firstMatch(sms);
        counterparty = match?.group(1)?.trim();
      }
    } else if (lowerSms.contains('paid to')) {
      if (lowerSms.contains('fuliza')) {
        subtype = MpesaSubtype.fuliza;
        counterparty = 'Fuliza M-PESA';
      } else {
        subtype = MpesaSubtype.buyGoods;
        final match = RegExp(r'paid to\s+(.*?)(?:\s+on|\.|\s*$)', caseSensitive: false).firstMatch(sms);
        counterparty = match?.group(1)?.trim();
      }
    } else if (lowerSms.contains('withdraw')) {
      subtype = MpesaSubtype.withdraw;
      final match = RegExp(r'from\s+(.*?)\s+new m-pesa', caseSensitive: false).firstMatch(sms);
      if (match != null) {
          final cp = match.group(1)?.trim();
          if (cp != null && cp.endsWith('.')) {
              counterparty = cp.substring(0, cp.length - 1).trim();
          } else {
              counterparty = cp;
          }
      }
    } else if (lowerSms.contains('bought') && lowerSms.contains('of airtime')) {
      subtype = MpesaSubtype.airtime;
      counterparty = 'Safaricom';
    } else if (lowerSms.contains('transferred to m-shwari')) {
      subtype = MpesaSubtype.mshwari;
      type = TransactionType.transfer;
      counterparty = 'M-Shwari';
    } else if (lowerSms.contains('transferred from m-shwari')) {
      subtype = MpesaSubtype.mshwari;
      type = TransactionType.transfer;
      counterparty = 'M-Shwari';
    } else if (lowerSms.contains('transferred to kcb m-pesa')) {
      subtype = MpesaSubtype.kcb;
      type = TransactionType.transfer;
      counterparty = 'KCB M-PESA';
    } else if (lowerSms.contains('transferred from kcb m-pesa')) {
      subtype = MpesaSubtype.kcb;
      type = TransactionType.transfer;
      counterparty = 'KCB M-PESA';
    }
    
    // Override subtype if fuliza was used during another transaction
    if (lowerSms.contains('fuliza m-pesa amount is')) {
      subtype = MpesaSubtype.fuliza;
    }

    final amountMatch = _amountRegExp.firstMatch(sms);
    if (amountMatch == null) {
      return UnparsedTransaction(sms, 'Could not extract amount');
    }
    final amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.parse(amountStr);

    final balanceMatch = _balanceRegExp.firstMatch(sms);
    double balance = 0.0;
    if (balanceMatch != null) {
      final balanceStr = balanceMatch.group(1)!.replaceAll(',', '');
      balance = double.parse(balanceStr);
    }

    final dateMatch = _dateRegExp.firstMatch(sms);
    DateTime timestamp = DateTime.now();
    if (dateMatch != null) {
      final dateStr = dateMatch.group(1)!;
      final timeStr = dateMatch.group(2)!;
      timestamp = _parseDate(dateStr, timeStr);
    }

    return ParsedTransaction(
      transactionCode: code,
      type: type,
      subtype: subtype,
      amount: amount,
      counterparty: counterparty,
      balance: balance,
      timestamp: timestamp,
      rawSms: sms,
    );
  }

  static DateTime _parseDate(String dateStr, String timeStr) {
    try {
      // dateStr: DD/MM/YY or DD/MM/YYYY
      final dateParts = dateStr.split('/');
      int day = int.parse(dateParts[0]);
      int month = int.parse(dateParts[1]);
      int year = int.parse(dateParts[2]);
      if (year < 100) {
        year += 2000;
      }

      // timeStr: HH:MM AM/PM
      final timeParts = timeStr.split(' ');
      final hm = timeParts[0].split(':');
      int hour = int.parse(hm[0]);
      int minute = int.parse(hm[1]);
      final isPM = timeParts.length > 1 && timeParts[1].toUpperCase() == 'PM';
      
      if (isPM && hour < 12) hour += 12;
      if (!isPM && hour == 12) hour = 0;

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      return DateTime.now();
    }
  }
}
