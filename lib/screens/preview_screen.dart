import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../models/document_model.dart';
import 'signature_screen.dart';

/// Layout para o PDF de BI/ID: frente e verso lado a lado ou empilhados
enum IdLayout { sideBySide, topBottom }

const _kBlue = Color(0xFF1A73E8);
const _kGreen = Color(0xFF1E8E3E);
const _kRed = Color(0xFFD93025);

// ─── Widget principal ─────────────────────────────────────────────────────────

class PreviewScreen extends StatefulWidget {
  final List<String> paths;
  final bool idMode;

  /// true quando o ML Kit devolveu directamente um PDF (Samsung S938B, etc.)
  final bool isPdfDirect;

  const PreviewScreen({
    super.key,
    required this.paths,
    this.idMode = false,
    this.isPdfDirect = false,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  // ─── Estado ───────────────────────────────────────────────────────────────
  String _ocrText = '';
  bool _isLoadingOcr = false;
  bool _isGeneratingPdf = false;
  File? _generatedPdf;
  Uint8List? _signatureBytes;

  final PageController _pageCtrl = PageController();
  // Notifier em vez de setState — o indicador de página (dots) e o OCR
  // precisam de saber a página actual, mas trocar de página não deve
  // reconstruir o ecrã inteiro (carrossel, painel de acções, etc.).
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier(0);
  int get _currentPageIndex => _currentPageNotifier.value;
  IdLayout _idLayout = IdLayout.sideBySide; // layout escolhido para BI

  /// Paths resolvidos prontos para usar (sem file:// URIs)
  List<String> _resolvedPaths = [];
  bool _resolving = true;

  static const _months = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez'
  ];

  // ─── Init ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (widget.isPdfDirect) {
      // PDF directo: resolve prefixos file:// de TODOS os paths (pode ter 2 no modo BI)
      _resolvedPaths = widget.paths.map(_cleanPath).toList();
      _resolving = false;
    } else {
      _resolvePaths();
    }
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _currentPageNotifier.dispose();
    super.dispose();
  }

  /// Remove prefixo file:// se presente
  String _cleanPath(String raw) {
    if (raw.startsWith('file://')) {
      try {
        return Uri.parse(raw).toFilePath();
      } catch (_) {}
    }
    return raw;
  }

  // ─── Resolver paths (modo imagens) ────────────────────────────────────────

  Future<void> _resolvePaths() async {
    final dir = await getApplicationDocumentsDirectory();
    final resolved = <String>[];

    for (int i = 0; i < widget.paths.length; i++) {
      final raw = _cleanPath(widget.paths[i]);
      if (raw.startsWith('/') && await File(raw).exists()) {
        resolved.add(raw);
        continue;
      }
      try {
        final dest =
            '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final xfile = XFile(raw);
        await xfile.saveTo(dest);
        resolved.add(dest);
      } catch (_) {
        resolved.add(raw);
      }
    }

    if (!mounted) return;
    setState(() {
      _resolvedPaths = resolved;
      _resolving = false;
    });
  }

  // ─── OCR ──────────────────────────────────────────────────────────────────

  Future<void> _runOCR() async {
    if (_resolvedPaths.isEmpty) return;
    setState(() {
      _isLoadingOcr = true;
      _ocrText = '';
    });
    try {
      final text =
          await OCRService.extractText(_resolvedPaths[_currentPageIndex]);
      if (!mounted) return;
      setState(() => _ocrText = text);
    } catch (e) {
      if (kDebugMode) debugPrint('Erro OCR: $e');
      if (!mounted) return;
      _showSnack('Não foi possível extrair texto desta imagem.');
    } finally {
      if (mounted) setState(() => _isLoadingOcr = false);
    }
  }

  /// OCR para o modo BI/ID — extrai texto de frente e verso (não só da
  /// página em exibição) e junta os dois resultados, identificados por lado.
  /// Quando as imagens vêm de um PDF direto do ML Kit (Samsung), extrai
  /// primeiro o JPEG/PNG embedded, tal como já é feito para gerar o PDF.
  Future<void> _runOcrId() async {
    if (_resolvedPaths.isEmpty) return;
    setState(() {
      _isLoadingOcr = true;
      _ocrText = '';
    });
    const labels = ['Frente', 'Verso'];
    final tmpFiles = <File>[];
    try {
      final parts = <String>[];
      for (int i = 0; i < _resolvedPaths.length; i++) {
        String ocrPath = _resolvedPaths[i];
        if (widget.isPdfDirect) {
          final bytes = await File(_resolvedPaths[i]).readAsBytes();
          final extracted = await _extractImageFromPdf(bytes);
          if (extracted == null) continue;
          final tmp = await _writeTempImage(extracted);
          tmpFiles.add(tmp);
          ocrPath = tmp.path;
        }
        final label = i < labels.length ? labels[i] : 'Página ${i + 1}';
        String text;
        try {
          text = await OCRService.extractText(ocrPath);
        } catch (e) {
          text = 'Não foi possível ler texto desta face.';
        }
        parts.add('$label:\n$text');
      }
      if (!mounted) return;
      setState(() => _ocrText = parts.join('\n\n'));
      if (parts.isEmpty) _showSnack('Não foi possível extrair texto do BI/ID.');
    } catch (e) {
      if (kDebugMode) debugPrint('Erro OCR BI/ID: $e');
      if (!mounted) return;
      _showSnack('Não foi possível extrair texto do BI/ID.');
    } finally {
      for (final t in tmpFiles) {
        try {
          await t.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isLoadingOcr = false);
    }
  }

  // ─── Assinatura ───────────────────────────────────────────────────────────

  Future<void> _addSignature() async {
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (bytes == null || !mounted) return;
    setState(() => _signatureBytes = bytes);
    _showSnack('Assinatura adicionada!');
  }

  // ─── Gerar PDF (modo imagens) ─────────────────────────────────────────────

  Future<void> _generatePDF() async {
    if (_resolvedPaths.isEmpty) {
      _showSnack('Sem imagens para converter.');
      return;
    }
    setState(() => _isGeneratingPdf = true);
    try {
      List<String> pathsForPdf = List.from(_resolvedPaths);

      if (widget.idMode && pathsForPdf.length >= 2) {
        final combined = await _combineIdImages(pathsForPdf);
        pathsForPdf = [combined];
      }

      final pdf = pw.Document();
      for (final path in pathsForPdf) {
        final f = File(path);
        if (!await f.exists()) continue;
        final bytes = await compute(PDFService.compressImage, path);
        await _addImagePage(pdf, renderBytes: bytes, ocrPath: path);
      }

      final saved = await _savePdfBytes(await pdf.save());
      if (!mounted) return;
      setState(() => _generatedPdf = saved);
      _showSnack('PDF guardado com sucesso!');
    } catch (e) {
      if (kDebugMode) debugPrint('Erro _generatePDF: $e');
      if (!mounted) return;
      _showSnack('Não foi possível gerar o PDF. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  // ─── Camada de texto pesquisável (OCR-to-PDF) ─────────────────────────────
  //
  // Adiciona uma página com a imagem e, sempre que o OCR tiver sucesso, uma
  // camada de texto invisível sobreposta alinhada às linhas detectadas —
  // é o que torna o PDF pesquisável/selecionável nos leitores ("sandwich
  // PDF"), sem alterar a aparência visual do documento.
  Future<void> _addImagePage(
    pw.Document pdf, {
    required Uint8List renderBytes,
    required String ocrPath,
  }) async {
    final image = pw.MemoryImage(renderBytes);

    RecognizedText? recognized;
    Size? origSize;
    try {
      recognized = await OCRService.recognize(ocrPath);
      origSize = await _decodeImageSize(await File(ocrPath).readAsBytes());
    } catch (e) {
      if (kDebugMode) debugPrint('OCR indisponível ao gerar PDF: $e');
    }

    final sig =
        _signatureBytes != null ? pw.MemoryImage(_signatureBytes!) : null;

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(16),
      build: (ctx) {
        final aW = ctx.page.pageFormat.availableWidth;
        final aH = ctx.page.pageFormat.availableHeight;
        final imgW = (image.width ?? 1).toDouble();
        final imgH = (image.height ?? 1).toDouble();
        final rect = _containRect(aW, aH, imgW, imgH);

        return pw.Stack(children: [
          pw.Positioned(
            left: rect.x,
            top: rect.y,
            child: pw.SizedBox(
              width: rect.w,
              height: rect.h,
              child: pw.Image(image, fit: pw.BoxFit.fill),
            ),
          ),
          if (recognized != null && origSize != null)
            ..._ocrOverlay(
              recognized,
              imageSize: origSize,
              drawX: rect.x,
              drawY: rect.y,
              drawW: rect.w,
              drawH: rect.h,
            ),
          if (sig != null)
            pw.Positioned(
              bottom: 0,
              right: 0,
              child: pw.Container(
                width: 160,
                height: 60,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  color: PdfColors.white,
                ),
                child: pw.Center(child: pw.Image(sig)),
              ),
            ),
        ]);
      },
    ));
  }

  /// Calcula o retângulo (x, y, largura, altura) que a imagem ocupa quando
  /// desenhada dentro de uma área de [boxW]x[boxH] preservando a proporção
  /// (equivalente a BoxFit.contain, mas calculado à mão para podermos
  /// alinhar a camada de texto invisível ao mesmo retângulo).
  ({double x, double y, double w, double h}) _containRect(
      double boxW, double boxH, double imgW, double imgH) {
    final scale = math.min(boxW / imgW, boxH / imgH);
    final w = imgW * scale;
    final h = imgH * scale;
    return (x: (boxW - w) / 2, y: (boxH - h) / 2, w: w, h: h);
  }

  Future<Size> _decodeImageSize(Uint8List bytes) async {
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
  /// PDF ([drawX]/[drawY]/[drawW]/[drawH]).
  List<pw.Widget> _ocrOverlay(
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

  // ─── Guardar PDF directo (modo isPdfDirect) ───────────────────────────────

  Future<void> _savePdfDirect() async {
    setState(() => _isGeneratingPdf = true);
    File? tmpOcrFile;
    try {
      final sourcePath = _resolvedPaths.first;
      final srcBytes = await File(sourcePath).readAsBytes();
      // Extrai o JPEG/PNG embedded no PDF do ML Kit — necessário para poder
      // desenhar a assinatura e a camada de OCR sobre o conteúdo real.
      final extractedImg = await _extractImageFromPdf(srcBytes);

      final List<int> pdfBytes;
      if (extractedImg != null) {
        final compressed =
            await compute(PDFService.compressBytes, extractedImg);
        tmpOcrFile = await _writeTempImage(extractedImg);
        final pdf = pw.Document();
        await _addImagePage(pdf,
            renderBytes: compressed, ocrPath: tmpOcrFile.path);
        pdfBytes = await pdf.save();
      } else {
        // Não foi possível extrair a imagem — mantém o PDF tal como veio do
        // scanner nativo (sem camada de OCR nem assinatura).
        pdfBytes = srcBytes;
        if (_signatureBytes != null) {
          _showSnack('Não foi possível aplicar a assinatura a este PDF.');
        }
      }

      final saved = await _savePdfBytes(pdfBytes);
      if (!mounted) return;
      setState(() => _generatedPdf = saved);
      _showSnack('PDF guardado com sucesso!');
    } catch (e) {
      if (kDebugMode) debugPrint('Erro _savePdfDirect: $e');
      if (!mounted) return;
      _showSnack('Não foi possível guardar o PDF. Tente novamente.');
    } finally {
      if (tmpOcrFile != null) {
        try {
          await tmpOcrFile.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  /// Escreve bytes de imagem num ficheiro temporário — o ML Kit só aceita
  /// caminhos de ficheiro (`InputImage.fromFilePath`), não bytes em memória.
  Future<File> _writeTempImage(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<File> _savePdfBytes(List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final name = widget.idMode
        ? 'BI_${now.day}_${_months[now.month - 1]}_${now.year}'
        : 'Documento ${now.day} ${_months[now.month - 1]} ${now.year}, '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // Nome de ficheiro em disco legível (em vez de epoch em milissegundos),
    // com segundos para evitar colisões entre gerações próximas.
    final datePart = '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final timePart = '${now.hour.toString().padLeft(2, '0')}h'
        '${now.minute.toString().padLeft(2, '0')}m'
        '${now.second.toString().padLeft(2, '0')}';
    final filePrefix = widget.idMode ? 'BI' : 'Documento';
    final dest = File('${dir.path}/${filePrefix}_${datePart}_$timePart.pdf');
    await dest.writeAsBytes(bytes);
    await StorageService.saveDocument(
        DocumentModel(name: name, path: dest.path, type: 'pdf', date: now));
    return dest;
  }

  // ─── Combinar imagens BI ──────────────────────────────────────────────────

  Future<String> _combineIdImages(List<String> paths) async {
    final images = <ui.Image>[];
    for (final p in paths) {
      final f = File(p);
      if (!await f.exists()) continue;
      final bytes = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      images.add(frame.image);
    }
    if (images.length < 2) return paths.first;

    const gap = 20;
    final maxH = images.map((i) => i.height).reduce((a, b) => a > b ? a : b);
    final totalW = images.fold<int>(0, (s, i) => s + i.width) + gap;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
        recorder, Rect.fromLTWH(0, 0, totalW.toDouble(), maxH.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0, 0, totalW.toDouble(), maxH.toDouble()),
        Paint()..color = Colors.white);

    double offsetX = 0;
    for (final img in images) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(offsetX, (maxH - img.height) / 2, img.width.toDouble(),
            img.height.toDouble()),
        Paint(),
      );
      offsetX += img.width + gap;
    }

    final picture = recorder.endRecording();
    final combined = await picture.toImage(totalW, maxH);
    final byteData = await combined.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final dir = await getApplicationDocumentsDirectory();
    final out =
        File('${dir.path}/bi_${DateTime.now().millisecondsSinceEpoch}.png');
    await out.writeAsBytes(pngBytes);
    return out.path;
  }

  // ─── Partilhar ────────────────────────────────────────────────────────────

  Future<void> _share() async {
    if (_generatedPdf == null) return;
    await SharePlus.instance.share(ShareParams(
        files: [XFile(_generatedPdf!.path)],
        text: 'Documento digitalizado com MS ScanNow'));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ─── Sair sem guardar ─────────────────────────────────────────────────────

  /// Só há algo a perder se já existem páginas capturadas e o PDF ainda não
  /// foi guardado — caso contrário sair é sempre seguro.
  bool get _canLeaveWithoutConfirmation =>
      _generatedPdf != null || (_resolvedPaths.isEmpty && widget.paths.isEmpty);

  Future<bool> _confirmDiscard() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair sem guardar?'),
        content: const Text(
            'O PDF ainda não foi guardado. Se sair agora, a digitalização será perdida.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuar aqui')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _kRed),
            child: const Text('Sair sem guardar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canLeaveWithoutConfirmation,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final confirmed = await _confirmDiscard();
        if (!confirmed || !context.mounted) return;
        Navigator.of(context).pop();
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    // Modo PDF directo: usa SfPdfViewer
    if (widget.isPdfDirect) return _buildDirectPdfScaffold();

    // Modo imagens: aguarda resolução
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(
            widget.idMode ? 'BI / ID — Pré-visualização' : 'Pré-visualização'),
        centerTitle: true,
        actions: [
          if (_generatedPdf != null)
            IconButton(icon: const Icon(Icons.share), onPressed: _share),
        ],
      ),
      body: _resolving
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(child: _buildImageCarousel()),
                _buildImageActionPanel(),
              ],
            ),
    );
  }

  // ─── Vista PDF directo ────────────────────────────────────────────────────

  // ─── Vista BI/ID com PDFs (modo Samsung) ─────────────────────────────────

  Widget _buildIdPdfScaffold() {
    final front = _resolvedPaths.isNotEmpty ? _resolvedPaths[0] : null;
    final back = _resolvedPaths.length > 1 ? _resolvedPaths[1] : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('BI / ID — Frente e Verso'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_generatedPdf != null)
            IconButton(icon: const Icon(Icons.share), onPressed: _share),
        ],
      ),
      body: Column(
        children: [
          // ── Selector de layout ────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Layout no PDF',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: _LayoutOption(
                      label: 'Lado a lado',
                      icon: Icons.view_week_outlined,
                      selected: _idLayout == IdLayout.sideBySide,
                      onTap: () =>
                          setState(() => _idLayout = IdLayout.sideBySide),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LayoutOption(
                      label: 'Cima / Baixo',
                      icon: Icons.table_rows_outlined,
                      selected: _idLayout == IdLayout.topBottom,
                      onTap: () =>
                          setState(() => _idLayout = IdLayout.topBottom),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Pré-visualização das páginas ──────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _idLayout == IdLayout.sideBySide
                  ? Row(children: [
                      Expanded(
                          child: _IdPdfPreview(path: front, label: 'Frente')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _IdPdfPreview(path: back, label: 'Verso')),
                    ])
                  : Column(children: [
                      Expanded(
                          child: _IdPdfPreview(path: front, label: 'Frente')),
                      const SizedBox(height: 12),
                      Expanded(
                          child: _IdPdfPreview(path: back, label: 'Verso')),
                    ]),
            ),
          ),

          // ── Painel de acções ──────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_signatureBytes != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.draw, color: _kGreen, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Image.memory(_signatureBytes!,
                                height: 36, fit: BoxFit.contain)),
                        GestureDetector(
                          onTap: () => setState(() => _signatureBytes = null),
                          child:
                              const Icon(Icons.close, color: _kGreen, size: 16),
                        ),
                      ]),
                    ),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingOcr ? null : _runOcrId,
                        icon: _isLoadingOcr
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kBlue))
                            : const Icon(Icons.text_fields, size: 18),
                        label: Text(_isLoadingOcr ? 'A extrair...' : 'OCR'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kBlue,
                          side:
                              BorderSide(color: _kBlue.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addSignature,
                        icon: Icon(
                            _signatureBytes != null
                                ? Icons.draw
                                : Icons.draw_outlined,
                            size: 18),
                        label: Text(
                            _signatureBytes != null ? 'Assinado' : 'Assinar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kGreen,
                          side:
                              BorderSide(color: _kGreen.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isGeneratingPdf ? null : _savePdfBi,
                      style: FilledButton.styleFrom(
                        backgroundColor: _kBlue,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isGeneratingPdf
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_alt),
                      label: Text(_isGeneratingPdf
                          ? 'A gerar PDF...'
                          : _generatedPdf != null
                              ? 'Guardado ✓'
                              : 'Guardar PDF'),
                    ),
                  ),
                  if (_generatedPdf != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Partilhar PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: BorderSide(color: _kRed.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                  if (_ocrText.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F2F5),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: _kBlue.withValues(alpha: 0.2)),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(_ocrText,
                            style: const TextStyle(fontSize: 13, height: 1.6)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Gera um PDF A4 combinando os dois scans do BI.
  /// — Modo imagem (isPdfDirect=false): combina as duas imagens numa só página.
  /// — Modo PDF directo (isPdfDirect=true, Samsung): cada scan fica numa página
  ///   com label, pois não é possível renderizar PDFs como imagens sem plugin nativo.
  /// Ponto de entrada para guardar o BI/ID.
  /// — isPdfDirect=false (imagens JPEG/PNG): usa _generatePDF que chama
  ///   _combineIdImages para juntar frente+verso numa só imagem → 1 página PDF.
  /// — isPdfDirect=true (PDFs Samsung ML Kit): faz merge dos PDFs em série
  ///   num único ficheiro, copiando as páginas de cada scan.
  Future<void> _savePdfBi() async {
    if (widget.isPdfDirect) {
      await _mergePdfsDirect();
    } else {
      await _generatePDF();
    }
  }

  /// Extrai a imagem JPEG/PNG embedded dentro de cada PDF do Samsung ML Kit.
  /// Os PDFs gerados pelo ML Kit são wrappers simples em torno de uma imagem —
  /// podemos extrair os bytes da imagem directamente sem renderização nativa.
  Future<Uint8List?> _extractImageFromPdf(Uint8List pdfBytes) async {
    try {
      // Procurar JPEG embedded (SOI marker: FF D8 FF)
      for (int i = 0; i < pdfBytes.length - 2; i++) {
        if (pdfBytes[i] == 0xFF &&
            pdfBytes[i + 1] == 0xD8 &&
            pdfBytes[i + 2] == 0xFF) {
          // Encontrou início de JPEG — procurar o EOI (FF D9) a partir daqui
          // para a frente. Procurar a partir do fim do ficheiro (como antes)
          // apanhava a ÚLTIMA ocorrência em todo o PDF, que pode estar depois
          // do trailer/xref e incluir lixo binário no JPEG extraído.
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

  /// Gera o PDF final combinando frente e verso numa só página, com camada
  /// de OCR pesquisável por lado. Para PDFs Samsung: extrai a imagem
  /// embedded de cada scan antes de incluir.
  Future<void> _mergePdfsDirect() async {
    if (_resolvedPaths.isEmpty) return;
    setState(() => _isGeneratingPdf = true);
    const labels = ['Frente', 'Verso'];
    final tmpFiles = <File>[];
    try {
      final items = <({
        String label,
        pw.MemoryImage image,
        Size origSize,
        RecognizedText? recognized
      })>[];

      for (int i = 0; i < _resolvedPaths.length; i++) {
        final f = File(_resolvedPaths[i]);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        if (bytes.length < 4) continue;

        final isPdf = bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46;

        final Uint8List? rawImage =
            isPdf ? await _extractImageFromPdf(bytes) : bytes;
        if (rawImage == null)
          continue; // não conseguiu extrair — ignora este lado

        final compressed = await compute(PDFService.compressBytes, rawImage);
        final origSize = await _decodeImageSize(rawImage);

        RecognizedText? recognized;
        try {
          final tmp = await _writeTempImage(rawImage);
          tmpFiles.add(tmp);
          recognized = await OCRService.recognize(tmp.path);
        } catch (e) {
          if (kDebugMode) debugPrint('OCR indisponível (BI lado $i): $e');
        }

        items.add((
          label: i < labels.length ? labels[i] : '',
          image: pw.MemoryImage(compressed),
          origSize: origSize,
          recognized: recognized,
        ));
      }

      if (items.isEmpty) {
        _showSnack('Não foi possível extrair as imagens dos PDFs.');
        return;
      }
      final failedCount = _resolvedPaths.length - items.length;

      final sig =
          _signatureBytes != null ? pw.MemoryImage(_signatureBytes!) : null;
      final isLandscape = _idLayout == IdLayout.sideBySide && items.length >= 2;

      final output = pw.Document();
      output.addPage(pw.Page(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) {
          final aWFull = ctx.page.pageFormat.availableWidth;
          final aHFull = ctx.page.pageFormat.availableHeight;
          const labelH = 14.0;
          const gap = 12.0;
          const sigReserve = 72.0;
          final aH = aHFull - (sig != null ? sigReserve : 0.0);

          final widgets = <pw.Widget>[];

          if (isLandscape) {
            final slotW = (aWFull - gap * (items.length - 1)) / items.length;
            double slotX = 0;
            for (final item in items) {
              widgets.add(pw.Positioned(
                left: slotX,
                top: 0,
                child: pw.Text(item.label,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
              ));
              final imgW = (item.image.width ?? 1).toDouble();
              final imgH = (item.image.height ?? 1).toDouble();
              final rect = _containRect(slotW, aH - labelH, imgW, imgH);
              final drawX = slotX + rect.x;
              final drawY = labelH + rect.y;
              widgets.add(pw.Positioned(
                left: drawX,
                top: drawY,
                child: pw.SizedBox(
                  width: rect.w,
                  height: rect.h,
                  child: pw.Image(item.image, fit: pw.BoxFit.fill),
                ),
              ));
              if (item.recognized != null) {
                widgets.addAll(_ocrOverlay(item.recognized!,
                    imageSize: item.origSize,
                    drawX: drawX,
                    drawY: drawY,
                    drawW: rect.w,
                    drawH: rect.h));
              }
              slotX += slotW + gap;
            }
          } else {
            final slotH = (aH - gap * (items.length - 1)) / items.length;
            double slotY = 0;
            for (final item in items) {
              widgets.add(pw.Positioned(
                left: 0,
                top: slotY,
                child: pw.Text(item.label,
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
              ));
              final imgW = (item.image.width ?? 1).toDouble();
              final imgH = (item.image.height ?? 1).toDouble();
              final rect = _containRect(aWFull, slotH - labelH, imgW, imgH);
              final drawX = rect.x;
              final drawY = slotY + labelH + rect.y;
              widgets.add(pw.Positioned(
                left: drawX,
                top: drawY,
                child: pw.SizedBox(
                  width: rect.w,
                  height: rect.h,
                  child: pw.Image(item.image, fit: pw.BoxFit.fill),
                ),
              ));
              if (item.recognized != null) {
                widgets.addAll(_ocrOverlay(item.recognized!,
                    imageSize: item.origSize,
                    drawX: drawX,
                    drawY: drawY,
                    drawW: rect.w,
                    drawH: rect.h));
              }
              slotY += slotH + gap;
            }
          }

          if (sig != null) {
            widgets.add(pw.Positioned(
              left: aWFull - 160,
              top: aH + 8,
              child: pw.SizedBox(
                width: 160,
                height: 56,
                child: pw.Container(
                  decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColors.grey400, width: 0.5)),
                  child: pw.Center(child: pw.Image(sig)),
                ),
              ),
            ));
          }

          return pw.Stack(children: widgets);
        },
      ));

      final saved = await _savePdfBytes(await output.save());
      if (!mounted) return;
      setState(() => _generatedPdf = saved);
      _showSnack(failedCount > 0
          ? 'PDF do BI guardado — não foi possível ler ${failedCount == 1 ? "um dos lados" : "$failedCount lados"}.'
          : 'PDF do BI guardado!');
    } catch (e, s) {
      if (kDebugMode) debugPrint('Erro _mergePdfsDirect: $e\n$s');
      if (!mounted) return;
      _showSnack('Não foi possível gerar o PDF do BI. Tente novamente.');
    } finally {
      for (final t in tmpFiles) {
        try {
          await t.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Widget _buildDirectPdfScaffold() {
    // Modo BI com 2 PDFs — mostra preview lado a lado com selector de layout
    if (widget.idMode && _resolvedPaths.isNotEmpty) {
      return _buildIdPdfScaffold();
    }

    final pdfPath = _resolvedPaths.isNotEmpty
        ? _resolvedPaths.first
        : _cleanPath(widget.paths.first);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documento digitalizado'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_generatedPdf != null)
            IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Partilhar',
                onPressed: _share),
        ],
      ),
      body: Column(
        children: [
          // Viewer PDF
          Expanded(
            child: File(pdfPath).existsSync()
                ? SfPdfViewer.file(
                    File(pdfPath),
                    onDocumentLoadFailed: (d) =>
                        _showSnack('Erro ao abrir PDF: ${d.description}'),
                  )
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_outlined,
                            size: 56, color: Colors.grey),
                        SizedBox(height: 8),
                        Text('Não foi possível encontrar o ficheiro PDF.'),
                      ],
                    ),
                  ),
          ),

          // Painel inferior COM SafeArea
          SafeArea(
            top: false,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prévia da assinatura
                  if (_signatureBytes != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: _kGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.draw, color: _kGreen, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Image.memory(_signatureBytes!,
                                height: 36, fit: BoxFit.contain)),
                        GestureDetector(
                          onTap: () => setState(() => _signatureBytes = null),
                          child:
                              const Icon(Icons.close, color: _kGreen, size: 16),
                        ),
                      ]),
                    ),

                  Row(children: [
                    // Assinar
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addSignature,
                        icon: Icon(
                          _signatureBytes != null
                              ? Icons.draw
                              : Icons.draw_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _signatureBytes != null ? 'Assinado' : 'Assinar',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kGreen,
                          side:
                              BorderSide(color: _kGreen.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Guardar PDF
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _isGeneratingPdf ? null : _savePdfDirect,
                        style: FilledButton.styleFrom(
                          backgroundColor: _kBlue,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isGeneratingPdf
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_alt),
                        label: Text(_isGeneratingPdf
                            ? 'A guardar...'
                            : _generatedPdf != null
                                ? 'Guardado ✓'
                                : 'Guardar PDF'),
                      ),
                    ),
                  ]),

                  // Partilhar (após guardar)
                  if (_generatedPdf != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Partilhar PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _kRed,
                          side: BorderSide(color: _kRed.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Carrossel de imagens ─────────────────────────────────────────────────

  Widget _buildImageCarousel() {
    if (widget.idMode) return _buildIdPreview();

    // A imagem nunca é mostrada maior que a largura do ecrã (BoxFit.contain)
    // — descodificar ao tamanho real da câmara (ex.: 4000px) é desperdício.
    final cacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .round();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _resolvedPaths.length,
            onPageChanged: (i) => _currentPageNotifier.value = i,
            itemBuilder: (_, i) {
              final f = File(_resolvedPaths[i]);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: f.existsSync()
                      ? Image.file(f,
                          fit: BoxFit.contain, cacheWidth: cacheWidth)
                      : const Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 64, color: Colors.grey)),
                ),
              );
            },
          ),
        ),
        if (_resolvedPaths.length > 1)
          ValueListenableBuilder<int>(
            valueListenable: _currentPageNotifier,
            builder: (_, current, __) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  _resolvedPaths.length,
                  (i) => Container(
                        width: i == current ? 16 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 8),
                        decoration: BoxDecoration(
                          color: i == current ? _kBlue : Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )),
            ),
          ),
        if (_signatureBytes != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4EA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGreen.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.draw, color: _kGreen, size: 16),
              const SizedBox(width: 8),
              Expanded(
                  child: Image.memory(_signatureBytes!,
                      height: 32, fit: BoxFit.contain)),
              GestureDetector(
                onTap: () => setState(() => _signatureBytes = null),
                child: const Icon(Icons.close, color: _kGreen, size: 16),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _buildIdPreview() {
    // Cada lado ocupa ~metade da largura do ecrã (Row com 2 Expanded).
    final cacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context) /
            2)
        .round();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _resolvedPaths.length; i++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: File(_resolvedPaths[i]).existsSync()
                    ? Image.file(File(_resolvedPaths[i]),
                        fit: BoxFit.cover, cacheWidth: cacheWidth)
                    : const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.grey)),
              ),
            ),
            if (i < _resolvedPaths.length - 1) const SizedBox(width: 12),
          ],
        ],
      ),
    );
  }

  // ─── Painel de acções (modo imagens) ──────────────────────────────────────

  Widget _buildImageActionPanel() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.text_fields,
                  label: _isLoadingOcr ? 'A extrair...' : 'OCR',
                  loading: _isLoadingOcr,
                  color: _kBlue,
                  bg: const Color(0xFFE8F0FE),
                  onTap: _isLoadingOcr
                      ? null
                      : (widget.idMode ? _runOcrId : _runOCR),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: _signatureBytes != null
                      ? Icons.draw
                      : Icons.draw_outlined,
                  label: _signatureBytes != null ? 'Assinado' : 'Assinar',
                  color: _kGreen,
                  bg: const Color(0xFFE6F4EA),
                  onTap: _addSignature,
                ),
              ),
              if (_generatedPdf != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.share_outlined,
                    label: 'Partilhar',
                    color: _kRed,
                    bg: const Color(0xFFFCE8E6),
                    onTap: _share,
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isGeneratingPdf
                    ? null
                    : (widget.idMode ? _savePdfBi : _generatePDF),
                style: FilledButton.styleFrom(
                  backgroundColor: _kBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isGeneratingPdf
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(_isGeneratingPdf
                    ? 'A gerar PDF...'
                    : _generatedPdf != null
                        ? 'Guardado ✓'
                        : 'Guardar como PDF'),
              ),
            ),
            if (_ocrText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F2F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kBlue.withValues(alpha: 0.2)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(_ocrText,
                      style: const TextStyle(fontSize: 13, height: 1.6)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Botão compacto ───────────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bg;
  final VoidCallback? onTap;
  final bool loading;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    this.onTap,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            loading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2, color: color))
                : Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: color)),
          ],
        ),
      ),
    );
  }
}

// ─── Selector de layout ───────────────────────────────────────────────────────

class _LayoutOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _LayoutOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1A73E8).withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF1A73E8) : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color:
                    selected ? const Color(0xFF1A73E8) : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? const Color(0xFF1A73E8)
                        : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// ─── Pré-visualização de página BI ───────────────────────────────────────────

class _IdPdfPreview extends StatelessWidget {
  final String? path;
  final String label;
  const _IdPdfPreview({required this.path, required this.label});

  /// Verifica a assinatura de bytes do próprio ficheiro em vez de assumir
  /// por tipo global — no modo BI, um lado pode ser PDF (Samsung/ML Kit)
  /// e o outro uma imagem pura (fallback de câmara), mesmo com
  /// isPdfDirect == true para o par.
  bool _isPdf(String p) {
    if (p.toLowerCase().endsWith('.pdf')) return true;
    try {
      final raf = File(p).openSync();
      final header = raf.readSync(4);
      raf.closeSync();
      return header.length == 4 &&
          header[0] == 0x25 &&
          header[1] == 0x50 &&
          header[2] == 0x44 &&
          header[3] == 0x46;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (path == null || !File(path!).existsSync()) {
      content = Center(
        child: Icon(Icons.credit_card_outlined,
            size: 48, color: Colors.grey.shade400),
      );
    } else if (_isPdf(path!)) {
      content = SfPdfViewer.file(
        File(path!),
        canShowScrollHead: false,
        canShowScrollStatus: false,
      );
    } else {
      final cacheWidth = (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context) /
              2)
          .round();
      content =
          Image.file(File(path!), fit: BoxFit.contain, cacheWidth: cacheWidth);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: content,
      ),
    );
  }
}
