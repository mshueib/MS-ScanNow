import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'models/document_model.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();

  Hive.registerAdapter(DocumentModelAdapter());

  try {
    await Hive.openBox<DocumentModel>('documents');
  } catch (e) {
    // Caixa corrompida (ex.: app encerrada a meio de uma escrita) — melhor
    // recomeçar do zero do que a app nunca mais arrancar.
    if (kDebugMode) debugPrint('Hive box corrompida, a recriar: $e');
    await Hive.deleteBoxFromDisk('documents');
    await Hive.openBox<DocumentModel>('documents');
  }

  runApp(const ScannerApp());
}

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "MS ScanNow",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}
