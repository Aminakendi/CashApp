enum TransactionType { income, expense, transfer }
enum MpesaSubtype {
  send,
  receive,
  buy_goods,
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
  static final RegExp _codeRegExp = RegExp(r'^([A-Z0-9]{10})\s+Confirmed\.');
  static final RegExp _amountRegExp = RegExp(r'(?:Confirmed\.|received|Withdraw|bought|Transaction of|PM\.|AM\.)\s+Ksh([\d,]+\.\d{2})');
  static final RegExp _balanceRegExp = RegExp(r'New M-PESA balance is Ksh([\d,]+\.\d{2})');
  static final RegExp _dateRegExp = RegExp(r'on\s+(\d{1,2}/\d{1,2}/\d{2,4})\s+at\s+(\d{1,2}:\d{2}\s+[APM]{2})');

  static ParseResult parse(String sms) {
    if (sms.contains('Failed.')) {
      return UnparsedTransaction(sms, 'Failed transaction');
    }
    
    if (!sms.contains('Confirmed.')) {
      return UnparsedTransaction(sms, 'Missing Confirmed keyword');
    }

    final codeMatch = _codeRegExp.firstMatch(sms);
    if (codeMatch == null) {
      return UnparsedTransaction(sms, 'Could not extract transaction code');
    }
    final code = codeMatch.group(1)!;

    MpesaSubtype subtype = MpesaSubtype.unknown;
    TransactionType type = TransactionType.expense;
    String? counterparty;

    if (sms.contains('Reversal of transaction')) {
      subtype = MpesaSubtype.reversal;
      type = TransactionType.transfer;
    } else if (sms.contains('You have received')) {
      subtype = MpesaSubtype.receive;
      type = TransactionType.income;
      final match = RegExp(r'from\s+(.*?)(?:\s+on|\.|\s*$)').firstMatch(sms);
      counterparty = match?.group(1)?.trim();
    } else if (sms.contains('sent to')) {
      if (sms.contains('for account')) {
        subtype = MpesaSubtype.paybill;
        final match = RegExp(r'sent to\s+(.*?)\s+for account').firstMatch(sms);
        counterparty = match?.group(1)?.trim();
      } else {
        subtype = MpesaSubtype.send;
        final match = RegExp(r'sent to\s+(.*?)(?:\s+on|\.|\s*$)').firstMatch(sms);
        counterparty = match?.group(1)?.trim();
      }
    } else if (sms.contains('paid to')) {
      if (sms.contains('Fuliza')) {
        subtype = MpesaSubtype.fuliza;
        counterparty = 'Fuliza M-PESA';
      } else {
        subtype = MpesaSubtype.buy_goods;
        final match = RegExp(r'paid to\s+(.*?)(?:\s+on|\.|\s*$)').firstMatch(sms);
        counterparty = match?.group(1)?.trim();
      }
    } else if (sms.contains('Withdraw')) {
      subtype = MpesaSubtype.withdraw;
      final match = RegExp(r'from\s+(.*?)\s+New M-PESA').firstMatch(sms);
      if (match != null) {
          final cp = match.group(1)?.trim();
          if (cp != null && cp.endsWith('.')) {
              counterparty = cp.substring(0, cp.length - 1).trim();
          } else {
              counterparty = cp;
          }
      }
    } else if (sms.contains('bought') && sms.contains('of airtime')) {
      subtype = MpesaSubtype.airtime;
      counterparty = 'Safaricom';
    } else if (sms.contains('transferred to M-Shwari')) {
      subtype = MpesaSubtype.mshwari;
      type = TransactionType.transfer;
      counterparty = 'M-Shwari';
    } else if (sms.contains('transferred from M-Shwari')) {
      subtype = MpesaSubtype.mshwari;
      type = TransactionType.transfer;
      counterparty = 'M-Shwari';
    } else if (sms.contains('transferred to KCB M-PESA')) {
      subtype = MpesaSubtype.kcb;
      type = TransactionType.transfer;
      counterparty = 'KCB M-PESA';
    } else if (sms.contains('transferred from KCB M-PESA')) {
      subtype = MpesaSubtype.kcb;
      type = TransactionType.transfer;
      counterparty = 'KCB M-PESA';
    }
    
    // Override subtype if fuliza was used during another transaction
    if (sms.contains('Fuliza M-PESA amount is')) {
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
