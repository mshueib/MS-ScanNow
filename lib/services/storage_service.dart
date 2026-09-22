import 'dart:io';
import 'package:hive/hive.dart';
import '../models/document_model.dart';

class StorageService {
  static const boxName = 'documents';

  static Box<DocumentModel> get _box => Hive.box<DocumentModel>(boxName);

  static Future<void> saveDocument(DocumentModel doc) async {
    await _box.add(doc);
  }

  static List<DocumentModel> getDocuments() {
    return _box.values.toList().reversed.toList();
  }

  /// Deleta usando a chave real do Hive — seguro mesmo após reordenações.
  /// Também apaga o ficheiro em disco, evitando órfãos que continuam a
  /// ocupar armazenamento depois de "eliminados" da app.
  static Future<void> deleteDocument(DocumentModel doc) async {
    try {
      final file = File(doc.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Se o ficheiro não puder ser apagado (ex.: já não existe), o registo
      // Hive é removido na mesma — não deixar o documento "preso".
    }
    await doc.delete();
  }

  /// Apaga vários documentos de uma vez (seleção múltipla no Histórico),
  /// incluindo os ficheiros em disco.
  static Future<void> deleteMany(List<DocumentModel> docs) async {
    for (final doc in docs) {
      try {
        final file = File(doc.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
      try {
        await doc.delete();
      } catch (_) {}
    }
  }

  /// Apaga todos os documentos, incluindo os ficheiros em disco.
  static Future<void> deleteAll() async {
    for (final doc in _box.values.toList()) {
      try {
        final file = File(doc.path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    await _box.clear();
  }
}
