import 'package:flutter/material.dart';
import 'package:sitemark/app.dart';
import 'package:sitemark/src/rust/frb_generated.dart';

export 'package:sitemark/app.dart' show MyApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const MyApp());
}
