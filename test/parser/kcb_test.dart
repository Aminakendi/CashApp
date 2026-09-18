import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/parser/mpesa_parser.dart';

void main() {
  test('KCB test', () {
    final sms = "UIBFY5S6FJ Confirmed. Ksh3,000.00 transfered to KCB M-PESA account on 11/9/26 at 1:59 PM. New M-PESA balance is Ksh363.42, new KCB M-PESA Saving account balance is Ksh3,000.29.";
    final parsed = MpesaParser.parse(sms);
    print(parsed);
  });
}
