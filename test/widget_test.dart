// Teste de fumo: garante que a app arranca (com uma caixa Hive de teste) e
// mostra o ecrã inicial, sem depender de nenhum estado deixado por outros
// testes.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:smart_doc_scanner/main.dart';
import 'package:smart_doc_scanner/models/document_model.dart';

void main() {
  testWidgets('App arranca e mostra o ecrã principal', (tester) async {
    final tempDir = await Directory.systemTemp.createTemp('ms_scannow_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(DocumentModelAdapter());
    await Hive.openBox<DocumentModel>('documents');

    addTearDown(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    await tester.pumpWidget(const ScannerApp());
    await tester.pumpAndSettle();

    expect(find.text('MS ScanNow'), findsWidgets);
    expect(find.byIcon(Icons.document_scanner), findsWidgets);
  });
}
