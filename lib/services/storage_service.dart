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
  static Future<void> deleteDocument(DocumentModel doc) async {
    await doc.delete();
  }
}
