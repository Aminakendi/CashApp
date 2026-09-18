import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mpesa_tracker/database/database.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Extract KCB transaction', (tester) async {
    final db = AppDatabase();
    final results = await db.select(db.transactions).get();
        
    for (var r in results) {
      if (r.amount == 8000.0 && r.mpesaSubtype == 'unknown') {
        print('FOUND KCB TX: id=${r.id}, rawSmsText=${r.rawSmsText}');
      }
    }
  });
}
