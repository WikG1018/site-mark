import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/features/settings/sections/diagnostics_section_screen.dart';
import 'package:sitemark/l10n/app_strings.dart';

void main() {
  testWidgets('always explains local-only diagnostics and share privacy', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        locale: Locale('zh'),
        home: DiagnosticsSectionScreen(),
      ),
    );

    expect(find.textContaining('诊断记录只保存在本机，不会自动上传'), findsOneWidget);
    expect(find.textContaining('不包含照片、项目名称'), findsOneWidget);
    expect(find.text('生成并分享诊断包'), findsOneWidget);
  });
}
