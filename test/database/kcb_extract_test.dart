import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/database/database.dart';
import 'package:drift/drift.dart';

void main() {
  test('Extract KCB transaction', () async {
    final db = AppDatabase();
    final results = await (db.select(db.transactions)
          ..where((t) => t.amount.equals(8000))
          ..where((t) => t.mpesaSubtype.equals('unknown')))
        .get();
        
    for (var r in results) {
      print('FOUND KCB TX: id=${r.id}, rawSmsText=${r.rawSmsText}');
    }
  });
}
