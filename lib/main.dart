import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/document_model.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(DocumentModelAdapter());

  await Hive.openBox<DocumentModel>('documents');

  runApp(const ScannerApp());
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Smart Scanner",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}
