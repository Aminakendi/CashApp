import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/parser/mpesa_parser.dart';

void main() {
  group('MpesaParser Tests', () {
    test('1. Parse Send Money with commas', () {
      const sms =
          'PXX2ABC123 Confirmed. Ksh1,500.00 sent to JOHN DOE 0712345678 on 24/10/21 at 12:34 PM. New M-PESA balance is Ksh10,000.00. Transaction cost, Ksh22.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.transactionCode, 'PXX2ABC123');
      expect(parsed.type, TransactionType.expense);
      expect(parsed.subtype, MpesaSubtype.send);
      expect(parsed.amount, 1500.00);
      expect(parsed.counterparty, 'JOHN DOE 0712345678');
      expect(parsed.balance, 10000.00);
    });

    test('2. Parse Receive Money', () {
      const sms =
          'PXX3DEF456 Confirmed. You have received Ksh2,000.00 from JANE SMITH 0723456789 on 24/10/21 at 1:00 PM. New M-PESA balance is Ksh12,000.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.transactionCode, 'PXX3DEF456');
      expect(parsed.type, TransactionType.income);
      expect(parsed.subtype, MpesaSubtype.receive);
      expect(parsed.amount, 2000.00);
      expect(parsed.counterparty, 'JANE SMITH 0723456789');
      expect(parsed.balance, 12000.00);
    });

    test('3. Parse Buy Goods', () {
      const sms =
          'PXX4GHI789 Confirmed. Ksh500.00 paid to SUPERMARKET LTD. on 24/10/21 at 2:15 PM. New M-PESA balance is Ksh11,500.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.buyGoods);
      expect(parsed.amount, 500.00);
    });

    test('4. Parse Paybill', () {
      const sms =
          'PXX5JKL012 Confirmed. Ksh3,000.00 sent to KPLC PREPAID for account 1234567890 on 24/10/21 at 3:30 PM. New M-PESA balance is Ksh8,500.00. Transaction cost, Ksh22.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.paybill);
      expect(parsed.amount, 3000.00);
    });

    test('5. Parse Withdraw', () {
      const sms =
          'PXX6MNO345 Confirmed. on 24/10/21 at 4:45 PM Withdraw Ksh4,000.00 from AGENT NAME 123456. New M-PESA balance is Ksh4,500.00. Transaction cost, Ksh67.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.withdraw);
      expect(parsed.counterparty, 'AGENT NAME 123456');
    });

    test('6. Parse Airtime', () {
      const sms =
          'PXX7PQR678 Confirmed. You bought Ksh100.00 of airtime on 24/10/21 at 5:00 PM. New M-PESA balance is Ksh4,400.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.airtime);
    });

    test('7a. Parse Fuliza Repayment', () {
      const sms =
          'PXX9VWX234 Confirmed. Ksh500.00 paid to Fuliza M-PESA on 24/10/21 at 7:00 PM. New M-PESA balance is Ksh3,900.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.fuliza);
    });

    test('7b. Parse Fuliza Usage (During Send Money)', () {
      const sms =
          'PXX9VWX999 Confirmed. Ksh2,000.00 sent to JOHN DOE 0712345678 on 24/10/21 at 6:00 PM. New M-PESA balance is Ksh0.00. Fuliza M-PESA amount is Ksh500.00. Transaction cost, Ksh22.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      // Because "Fuliza M-PESA amount is" is present, the parser marks it as fuliza subtype.
      expect(parsed.subtype, MpesaSubtype.fuliza);
      expect(parsed.amount, 2000.00);
      expect(parsed.counterparty, 'JOHN DOE 0712345678');
    });

    test('8a. Parse M-Shwari Deposit', () {
      const sms =
          'PXX0YZA567 Confirmed. Ksh1,000.00 transferred to M-Shwari account on 24/10/21 at 8:00 PM. New M-PESA balance is Ksh2,900.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.mshwari);
      expect(parsed.type, TransactionType.transfer);
    });

    test('8b. Parse M-Shwari Withdrawal', () {
      const sms =
          'PXX0YZB888 Confirmed. Ksh1,000.00 transferred from M-Shwari account on 24/10/21 at 8:00 PM. New M-PESA balance is Ksh3,900.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.mshwari);
      expect(parsed.type, TransactionType.transfer);
    });

    test('8c. Parse KCB M-PESA Deposit', () {
      const sms =
          'PXX0YZC999 Confirmed. Ksh1,000.00 transferred to KCB M-PESA account on 24/10/21 at 8:00 PM. New M-PESA balance is Ksh2,900.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.kcb);
      expect(parsed.type, TransactionType.transfer);
    });

    test('8d. Parse KCB M-PESA Withdrawal', () {
      const sms =
          'PXX0YZD111 Confirmed. Ksh1,000.00 transferred from KCB M-PESA account on 24/10/21 at 8:00 PM. New M-PESA balance is Ksh3,900.00. Transaction cost, Ksh0.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.kcb);
      expect(parsed.type, TransactionType.transfer);
    });

    test('9a. Parse Reversed Transaction', () {
      const sms =
          'PXX0YZE222 Confirmed. Reversal of transaction PXX2ABC123 has been successfully completed on 24/10/21 at 8:00 PM. Ksh1,500.00 is returned to your M-PESA account. New M-PESA balance is Ksh11,500.00.';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.subtype, MpesaSubtype.reversal);
      expect(parsed.type, TransactionType.transfer);
      expect(parsed.amount, 1500.00);
    });

    test('9b. Parse Failed Transaction', () {
      const sms =
          'PXX0YZE333 Failed. Transaction of Ksh1,500.00 to JOHN DOE failed. Insufficient funds.';
      final parsed = MpesaParser.parse(sms);

      expect(parsed, isA<UnparsedTransaction>());
      expect((parsed as UnparsedTransaction).reason, 'Failed transaction');
    });

    test('10. Returns UnparsedTransaction for non-Mpesa SMS', () {
      const sms = 'Safaricom offers: Get 1GB for Ksh 50. Dial *544#';
      final parsed = MpesaParser.parse(sms);
      
      expect(parsed, isA<UnparsedTransaction>());
      expect((parsed as UnparsedTransaction).reason, 'Missing Confirmed keyword');
    });

    test('11. Returns UnparsedTransaction for malformed M-PESA SMS', () {
      const sms = 'PXX0YZX000 Confirmed. You have received Ksh from JANE SMITH. New M-PESA balance is Ksh12,000.00.';
      final parsed = MpesaParser.parse(sms);
      
      expect(parsed, isA<UnparsedTransaction>());
      expect((parsed as UnparsedTransaction).reason, 'Could not extract amount');
    });

    test('12. Parse Airtime without space and lowercase confirmed', () {
      const sms =
          'UI8FY5F40D confirmed.You bought Ksh10.00 of airtime on 8/9/26 at 12:41 PM.New M-PESA balance is Ksh1,561.42. Transaction cost, Ksh0.00. Amount you can transact within the day is 499,860.00. See all your balances now https://saf.cx/3wAmy';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.transactionCode, 'UI8FY5F40D');
      expect(parsed.subtype, MpesaSubtype.airtime);
      expect(parsed.amount, 10.00);
      expect(parsed.balance, 1561.42);
      expect(parsed.timestamp.hour, 12);
      expect(parsed.timestamp.minute, 41);
    });

    test('13. Parse M-Shwari Withdrawal without space before amount', () {
      const sms =
          'UI2FY4P5QM Confirmed.Ksh400.00 transferred from M-Shwari account on 2/9/26 at 10:22 AM. M-Shwari balance is Ksh23.30 .M-PESA balance is Ksh400.42 .Transaction cost Ksh.0.00';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.transactionCode, 'UI2FY4P5QM');
      expect(parsed.subtype, MpesaSubtype.mshwari);
      expect(parsed.type, TransactionType.transfer);
      expect(parsed.amount, 400.00);
      expect(parsed.balance, 400.42);
    });

    test('14. Parse M-Shwari Deposit without space before amount', () {
      const sms =
          'UI7FY5B2TW Confirmed.Ksh1,000.00 transferred to M-Shwari account on 7/9/26 at 1:36 PM. M-PESA balance is Ksh2,846.42 .New M-Shwari saving account balance is Ksh6,023.30. Transaction cost Ksh.0.00';
      final parsed = MpesaParser.parse(sms) as ParsedTransaction;

      expect(parsed.transactionCode, 'UI7FY5B2TW');
      expect(parsed.subtype, MpesaSubtype.mshwari);
      expect(parsed.type, TransactionType.transfer);
      expect(parsed.amount, 1000.00);
      expect(parsed.balance, 2846.42);
    });
  });
}
