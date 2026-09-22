import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../widgets/draggable_signature.dart' show SignaturePlacement;

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

  /// Extrai a imagem JPEG/PNG embedded dentro de um PDF simples (wrapper de
  /// uma única imagem, como os que o ML Kit do Samsung devolve). Faz uma
  /// pesquisa linear pelos bytes do ficheiro — para PDFs de vários MB isto
  /// pode demorar o suficiente para bloquear a isolate principal de forma
  /// visível, por isso é uma função top-level-safe para correr via
  /// `compute()`.
  static Uint8List? extractEmbeddedImage(Uint8List pdfBytes) {
    try {
      // Procurar JPEG embedded (SOI marker: FF D8 FF)
      for (int i = 0; i < pdfBytes.length - 2; i++) {
        if (pdfBytes[i] == 0xFF &&
            pdfBytes[i + 1] == 0xD8 &&
            pdfBytes[i + 2] == 0xFF) {
          // Encontrou início de JPEG — procurar o EOI (FF D9) a partir daqui
          // para a frente, para não apanhar lixo binário depois do trailer.
          // Nota: não se valida o resultado com um descodificador — um
          // descodificador Dart puro pode rejeitar variantes de JPEG que o
          // Android aceita perfeitamente (ex.: certas variantes de
          // subsampling), o que já causou a perda de imagens válidas.
          for (int j = i + 2; j < pdfBytes.length - 1; j++) {
            if (pdfBytes[j] == 0xFF && pdfBytes[j + 1] == 0xD9) {
              return pdfBytes.sublist(i, j + 2);
            }
          }
          // Sem EOI encontrado — pegar tudo até ao fim
          return pdfBytes.sublist(i);
        }
      }
      // Procurar PNG embedded (PNG signature: 89 50 4E 47)
      for (int i = 0; i < pdfBytes.length - 3; i++) {
        if (pdfBytes[i] == 0x89 &&
            pdfBytes[i + 1] == 0x50 &&
            pdfBytes[i + 2] == 0x4E &&
            pdfBytes[i + 3] == 0x47) {
          // PNG: procurar IEND chunk (49 45 4E 44 AE 42 60 82)
          for (int j = i + 8; j < pdfBytes.length - 7; j++) {
            if (pdfBytes[j] == 0x49 &&
                pdfBytes[j + 1] == 0x45 &&
                pdfBytes[j + 2] == 0x4E &&
                pdfBytes[j + 3] == 0x44) {
              return pdfBytes.sublist(i, j + 8);
            }
          }
          return pdfBytes.sublist(i);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Escreve bytes de imagem num ficheiro temporário — o ML Kit só aceita
  /// caminhos de ficheiro (`InputImage.fromFilePath`), não bytes em memória.
  static Future<File> writeTempImage(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Calcula o retângulo (x, y, largura, altura) que uma imagem ocupa
  /// quando desenhada dentro de uma área de [boxW]x[boxH] preservando a
  /// proporção (equivalente a BoxFit.contain, mas calculado à mão para se
  /// poder alinhar a camada de texto invisível ao mesmo retângulo).
  static ({double x, double y, double w, double h}) containRect(
      double boxW, double boxH, double imgW, double imgH) {
    final scale = math.min(boxW / imgW, boxH / imgH);
    final w = imgW * scale;
    final h = imgH * scale;
    return (x: (boxW - w) / 2, y: (boxH - h) / 2, w: w, h: h);
  }

  static Future<Size> decodeImageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size =
        Size(frame.image.width.toDouble(), frame.image.height.toDouble());
    frame.image.dispose();
    return size;
  }

  /// Gera os widgets de texto invisível alinhados às linhas detectadas pelo
  /// OCR, convertendo as coordenadas em pixels da imagem original
  /// ([imageSize]) para o retângulo onde a imagem foi desenhada na página
  /// PDF ([drawX]/[drawY]/[drawW]/[drawH]) — é o que torna o PDF
  /// pesquisável/selecionável, sem alterar a aparência visual do documento.
  static List<pw.Widget> ocrOverlay(
    RecognizedText recognized, {
    required Size imageSize,
    required double drawX,
    required double drawY,
    required double drawW,
    required double drawH,
  }) {
    if (imageSize.width == 0 || imageSize.height == 0) return const [];
    final widgets = <pw.Widget>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().isEmpty) continue;
        final box = line.boundingBox;
        widgets.add(pw.Positioned(
          left: drawX + (box.left / imageSize.width) * drawW,
          top: drawY + (box.top / imageSize.height) * drawH,
          child: pw.SizedBox(
            width: (box.width / imageSize.width) * drawW,
            height: (box.height / imageSize.height) * drawH,
            child: pw.FittedBox(
              fit: pw.BoxFit.fill,
              child: pw.Text(
                line.text,
                maxLines: 1,
                softWrap: false,
                style: const pw.TextStyle(
                  fontSize: 100,
                  color: PdfColors.black,
                  renderingMode: PdfTextRenderingMode.invisible,
                ),
              ),
            ),
          ),
        ));
      }
    }
    return widgets;
  }

  /// Desenha a assinatura (e, opcionalmente, a data) diretamente nos pixeis
  /// da imagem do documento, em vez de a colocar como uma camada vetorial
  /// separada no PDF. Isto garante que o resultado é sempre "o que se vê é
  /// o que se grava": a pré-visualização (que mostra a imagem, não o PDF
  /// completo) reflete sempre exatamente o que fica no ficheiro final, sem
  /// depender de como cada leitor de PDF interpreta camadas sobrepostas.
  static Future<Uint8List> bakeSignatureOntoImage(
    Uint8List imageBytes, {
    required Uint8List signatureBytes,
    required SignaturePlacement placement,
    String? dateLabel,
  }) async {
    final baseCodec = await ui.instantiateImageCodec(imageBytes);
    final baseFrame = await baseCodec.getNextFrame();
    final baseImage = baseFrame.image;

    final sigCodec = await ui.instantiateImageCodec(signatureBytes);
    final sigFrame = await sigCodec.getNextFrame();
    final sigImage = sigFrame.image;

    final imgW = baseImage.width.toDouble();
    final imgH = baseImage.height.toDouble();

    // Largura base da assinatura como fração da largura da imagem, para
    // ficar proporcional independentemente da resolução da fotografia.
    final sigW = imgW * 0.28 * placement.scale;
    final sigAspect = sigImage.height / sigImage.width;
    final sigH = sigW * sigAspect;

    final cx = placement.anchor.dx * imgW;
    final cy = placement.anchor.dy * imgH;
    final left =
        (cx - sigW / 2).clamp(0.0, math.max(0.0, imgW - sigW)).toDouble();
    final top =
        (cy - sigH / 2).clamp(0.0, math.max(0.0, imgH - sigH)).toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, imgW, imgH));
    canvas.drawImage(baseImage, Offset.zero, Paint());
    canvas.drawImageRect(
      sigImage,
      Rect.fromLTWH(
          0, 0, sigImage.width.toDouble(), sigImage.height.toDouble()),
      Rect.fromLTWH(left, top, sigW, sigH),
      Paint(),
    );

    if (placement.includeDate && dateLabel != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: dateLabel,
          style: TextStyle(
              color: const Color(0xFF333333),
              fontSize: sigH * 0.28,
              fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(left + (sigW - textPainter.width) / 2, top + sigH + 2),
      );
    }

    final picture = recorder.endRecording();
    final composited = await picture.toImage(imgW.round(), imgH.round());
    final byteData =
        await composited.toByteData(format: ui.ImageByteFormat.png);

    baseImage.dispose();
    sigImage.dispose();
    composited.dispose();

    final pngBytes = byteData!.buffer.asUint8List();
    // Reencoda para JPEG (via compressBytes) para manter o tamanho do
    // ficheiro previsível — a mesma compressão já usada em todo o resto do
    // pipeline de digitalização.
    return compressBytes(pngBytes);
  }

  /// Rasteriza a primeira página de um PDF para PNG usando o motor nativo
  /// de renderização (PdfRenderer no Android, PDFKit no iOS) — funciona com
  /// qualquer PDF válido, ao contrário de [extractEmbeddedImage], que só
  /// encontra a imagem se ela estiver guardada como bytes JPEG/PNG
  /// contíguos. É a via de recurso para PDFs cuja origem não é este app
  /// (ex.: alguns Samsung, onde o ML Kit devolve o PDF já pronto com a
  /// imagem codificada de outra forma internamente) ou PDFs importados de
  /// terceiros. Não é seguro para correr via `compute()` — usa canais de
  /// plataforma, que só funcionam na isolate principal.
  static Future<Uint8List?> rasterizeFirstPage(Uint8List pdfBytes) async {
    try {
      await for (final page in Printing.raster(pdfBytes, pages: [0], dpi: 200)) {
        return await page.toPng();
      }
    } catch (_) {}
    return null;
  }

  static const int _strongMaxDimension = 1280;
  static const int _strongJpegQuality = 45;

  /// Compressão mais agressiva que [compressBytes], usada apenas pela
  /// ferramenta "Comprimir" da Home. Método novo e independente — não altera
  /// [compressBytes]/[compressImage] nem os seus parâmetros, para não afetar
  /// nenhum dos fluxos existentes que já dependem deles.
  static Uint8List compressBytesStrong(Uint8List bytes) {
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return bytes;

    if (image.width > _strongMaxDimension || image.height > _strongMaxDimension) {
      image = img.copyResize(
        image,
        width: image.width > image.height ? _strongMaxDimension : null,
        height: image.height >= image.width ? _strongMaxDimension : null,
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: _strongJpegQuality));
  }
}
