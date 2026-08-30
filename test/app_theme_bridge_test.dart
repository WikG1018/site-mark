import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sitemark/app_theme.dart';

void main() {
  testWidgets(
    'cupertino bridge carries the resolved dark material brightness down',
    (tester) async {
      Brightness? observed;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.from(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: Brightness.dark,
            ),
          ),
          builder: bridgeCupertinoTheme,
          home: Builder(
            builder: (context) {
              observed = CupertinoTheme.of(context).brightness;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // CupertinoDynamicColors (large-title nav bars) resolve against this
      // brightness; a light default left a light bar over dark content.
      expect(observed, Brightness.dark);
    },
  );

  testWidgets('cupertino bridge stays light with a light theme', (
    tester,
  ) async {
    Brightness? observed;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.from(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
        ),
        builder: bridgeCupertinoTheme,
        home: Builder(
          builder: (context) {
            observed = CupertinoTheme.of(context).brightness;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(observed, Brightness.light);
  });
}
