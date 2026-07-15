import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sitemark/data/app_database.dart';
import 'package:sitemark/main.dart';
import 'package:sitemark/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(RustLib.init);

  testWidgets('starts at the project list', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      MyApp(database: database, initialLocale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('工程印记'), findsOneWidget);
    expect(find.text('新建项目'), findsWidgets);
  });
}
