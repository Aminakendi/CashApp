import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/parser/mpesa_parser.dart';

void main() {
  test('KCB test', () {
    const sms = "UIBFY5S6FJ Confirmed. Ksh3,000.00 transfered to KCB M-PESA account on 11/9/26 at 1:59 PM. New M-PESA balance is Ksh363.42, new KCB M-PESA Saving account balance is Ksh3,000.29.";
    final parsed = MpesaParser.parse(sms);
    debugPrint(parsed.toString());
  });

  test('KCB test withdrawal', () {
    const sms = "UIDFY61EB3 Confirmed. You have transfered Ksh1,000.00 from your KCB M-PESA account on 13/9/26 at 4:20 PM. KCB M-PESA Account balance is Ksh0.29. New M-PESA balance is Ksh1,011.42.";
    final parsed = MpesaParser.parse(sms);
    debugPrint(parsed.toString());
  });
}
