import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/document_model.dart';
import 'storage_service.dart';

/// Importa um PDF já existente no dispositivo para o Histórico — copia-o
/// para o armazenamento da app (mesma pasta usada por `PDFService.createPdf`)
/// e regista-o no Hive. Não faz qualquer inspeção do conteúdo do PDF: a
/// miniatura (`DocumentThumbnail`) já cai automaticamente no ícone genérico
/// quando `extractEmbeddedImage` não encontra uma imagem simples embutida,
/// como é normal em PDFs de terceiros com várias páginas ou texto.
class ImportService {
  /// Devolve `null` se o utilizador cancelar a seleção.
  static Future<DocumentModel?> importPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final picked = result?.files.single.path;
    if (picked == null) return null;

    final dir = await getApplicationDocumentsDirectory();
    final name = picked.split(Platform.pathSeparator).last;
    final dest = File(
        '${dir.path}/import_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await File(picked).copy(dest.path);

    final doc = DocumentModel(
      name: name.toLowerCase().endsWith('.pdf')
          ? name.substring(0, name.length - 4)
          : name,
      path: dest.path,
      type: 'pdf',
      date: DateTime.now(),
      pageCount: 1,
    );
    await StorageService.saveDocument(doc);
    return doc;
  }
}
