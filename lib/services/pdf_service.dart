import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

class PDFService {
  static const int _maxDimension = 1920;
  static const int _jpegQuality = 75;

  static Future<File> createPdf(List<String> paths) async {
    final pdf = pw.Document();

    for (final path in paths) {
      final compressed = await compute(compressImage, path);
      final image = pw.MemoryImage(compressed);
      pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(image))));
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(
      '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  /// Redimensiona e comprime uma imagem para uso em PDF. É uma função
  /// top-level-safe (estática, sem estado) para poder correr em isolate
  /// via `compute()` a partir de qualquer ecrã que gere PDFs.
  static Uint8List compressImage(String path) {
    return compressBytes(File(path).readAsBytesSync());
  }

  /// Igual a [compressImage], mas a partir de bytes já em memória — evita
  /// uma leitura de disco duplicada quando o chamador já tem os bytes
  /// (ex.: depois de verificar a assinatura do ficheiro).
  static Uint8List compressBytes(Uint8List bytes) {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    // Redimensiona mantendo proporção se for maior que _maxDimension
    if (image.width > _maxDimension || image.height > _maxDimension) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? _maxDimension : null,
        height: image.height >= image.width ? _maxDimension : null,
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: _jpegQuality));
  }
}
