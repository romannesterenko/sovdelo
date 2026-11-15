import 'package:flutter/material.dart';
import 'server_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProbeApp());
}

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'СовДело', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark, colorSchemeSeed: const Color(0xff56c89b),
      scaffoldBackgroundColor: const Color(0xff111b18), useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    ),
    home: const ServerPage(),
  );
}
