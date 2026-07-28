import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../services/ocr_service.dart';
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
  int _currentPage = 0;
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
      final text = await OCRService.extractText(_resolvedPaths[_currentPage]);
      if (!mounted) return;
      setState(() => _ocrText = text);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao extrair texto: $e');
    } finally {
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
        final bytes = await f.readAsBytes();
        final image = pw.MemoryImage(bytes);
        if (_signatureBytes != null) {
          final sig = pw.MemoryImage(_signatureBytes!);
          pdf.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Stack(children: [
              pw.Positioned.fill(
                  child: pw.Image(image, fit: pw.BoxFit.contain)),
              pw.Positioned(
                  bottom: 20,
                  right: 20,
                  child: pw.Container(
                    width: 160,
                    height: 60,
                    decoration: pw.BoxDecoration(
                      border:
                          pw.Border.all(color: PdfColors.grey400, width: 0.5),
                      color: PdfColors.white,
                    ),
                    child: pw.Center(child: pw.Image(sig)),
                  )),
            ]),
          ));
        } else {
          pdf.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(image))));
        }
      }

      final saved = await _savePdfBytes(await pdf.save());
      if (!mounted) return;
      setState(() => _generatedPdf = saved);
      _showSnack('PDF guardado com sucesso!');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao gerar PDF: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  // ─── Guardar PDF directo (modo isPdfDirect) ───────────────────────────────

  Future<void> _savePdfDirect() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final sourcePath = _resolvedPaths.first;
      final List<int> pdfBytes;

      if (_signatureBytes != null) {
        // Adiciona assinatura como nova página de rodapé
        final pdf = pw.Document();
        final srcBytes = await File(sourcePath).readAsBytes();
        final sig = pw.MemoryImage(_signatureBytes!);
        // Página com imagem thumbnail do PDF + assinatura
        pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Expanded(
                  child: pw.Center(
                      child: pw.Text('Documento digitalizado',
                          style: pw.TextStyle(fontSize: 18)))),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 200,
                  height: 80,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Center(child: pw.Image(sig)),
                ),
              ),
            ],
          ),
        ));
        pdfBytes = await pdf.save();
      } else {
        pdfBytes = await File(sourcePath).readAsBytes();
      }

      final saved = await _savePdfBytes(pdfBytes);
      if (!mounted) return;
      setState(() => _generatedPdf = saved);
      _showSnack('PDF guardado com sucesso!');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Erro ao guardar: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Future<File> _savePdfBytes(List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final name = widget.idMode
        ? 'BI_${now.day}_${_months[now.month - 1]}_${now.year}'
        : 'Documento ${now.day} ${_months[now.month - 1]} ${now.year}, '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final dest = File('${dir.path}/scan_${now.millisecondsSinceEpoch}.pdf');
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
    await Share.shareXFiles([XFile(_generatedPdf!.path)],
        text: 'Documento digitalizado com MS ScanNow');
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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
                          side: BorderSide(color: _kGreen.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
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
                  ]),
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
                          side: BorderSide(color: _kRed.withOpacity(0.5)),
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
          // Encontrou início de JPEG — procurar o fim (EOI marker: FF D9)
          for (int j = pdfBytes.length - 1; j > i + 2; j--) {
            if (pdfBytes[j] == 0xD9 && pdfBytes[j - 1] == 0xFF) {
              return pdfBytes.sublist(i, j + 1);
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

  /// Gera o PDF final combinando frente e verso numa só página.
  /// Para PDFs Samsung: extrai a imagem embedded antes de incluir.
  Future<void> _mergePdfsDirect() async {
    if (_resolvedPaths.isEmpty) return;
    setState(() => _isGeneratingPdf = true);
    try {
      final pw.ImageProvider? sig =
          _signatureBytes != null ? pw.MemoryImage(_signatureBytes!) : null;
      const labels = ['Frente', 'Verso'];

      final List<MapEntry<int, Uint8List>> pageImages = [];

      for (int i = 0; i < _resolvedPaths.length; i++) {
        final f = File(_resolvedPaths[i]);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        if (bytes.length < 4) continue;

        final isPdf = bytes[0] == 0x25 &&
            bytes[1] == 0x50 &&
            bytes[2] == 0x44 &&
            bytes[3] == 0x46;

        if (isPdf) {
          // Tentar extrair imagem embedded no PDF
          final extracted = await _extractImageFromPdf(bytes);
          if (extracted != null) {
            pageImages.add(MapEntry(i, extracted));
          }
          // Se não encontrar imagem, ignorar (melhor que mostrar texto)
        } else {
          pageImages.add(MapEntry(i, bytes));
        }
      }

      if (pageImages.isEmpty) {
        _showSnack('Não foi possível extrair as imagens dos PDFs.');
        return;
      }

      final output = pw.Document();
      final imgs = pageImages.map((e) => pw.MemoryImage(e.value)).toList();
      final idxs = pageImages.map((e) => e.key).toList();
      final isLandscape = _idLayout == IdLayout.sideBySide && imgs.length >= 2;

      output.addPage(pw.Page(
        pageFormat: isLandscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) {
          final aW = ctx.page.pageFormat.availableWidth;
          final aH =
              ctx.page.pageFormat.availableHeight - (sig != null ? 72.0 : 0.0);

          if (isLandscape) {
            final iW = (aW - 12.0 * (imgs.length - 1)) / imgs.length;
            return pw.Column(children: [
              pw.Row(children: [
                for (int j = 0; j < imgs.length; j++) ...[
                  pw.Container(
                    width: iW,
                    height: aH,
                    child: pw.Image(imgs[j], fit: pw.BoxFit.contain),
                  ),
                  if (j < imgs.length - 1) pw.SizedBox(width: 12),
                ],
              ]),
              if (sig != null) ...[
                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    width: 160,
                    height: 56,
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                            color: PdfColors.grey400, width: 0.5)),
                    child: pw.Center(child: pw.Image(sig)),
                  ),
                ),
              ],
            ]);
          } else {
            final iH = (aH - 12.0 * (imgs.length - 1)) / imgs.length;
            return pw.Column(children: [
              for (int j = 0; j < imgs.length; j++) ...[
                pw.Container(
                  width: double.infinity,
                  height: iH,
                  child: pw.Image(imgs[j], fit: pw.BoxFit.contain),
                ),
                if (j < imgs.length - 1) pw.SizedBox(height: 12),
              ],
              if (sig != null) ...[
                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    width: 160,
                    height: 56,
                    decoration: pw.BoxDecoration(
                        border: pw.Border.all(
                            color: PdfColors.grey400, width: 0.5)),
                    child: pw.Center(child: pw.Image(sig)),
                  ),
                ),
              ],
            ]);
          }
        },
      ));

      final saved = await _savePdfBytes(await output.save());
      if (!mounted) return;
      setState(() => _generatedPdf = saved);
      _showSnack('PDF do BI guardado!');
    } catch (e, s) {
      debugPrint('Erro _mergePdfsDirect: $e\n$s');
      if (!mounted) return;
      _showSnack('Erro ao gerar PDF: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  Widget _buildDirectPdfScaffold() {
    // Modo BI com 2 PDFs — mostra preview lado a lado com selector de layout
    if (widget.idMode && _resolvedPaths.length >= 1) {
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
            child: SfPdfViewer.file(
              File(pdfPath),
              onDocumentLoadFailed: (d) =>
                  _showSnack('Erro ao abrir PDF: ${d.description}'),
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
                        border: Border.all(color: _kGreen.withOpacity(0.3)),
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
                          side: BorderSide(color: _kGreen.withOpacity(0.5)),
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
                          side: BorderSide(color: _kRed.withOpacity(0.5)),
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

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: _resolvedPaths.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (_, i) {
              final f = File(_resolvedPaths[i]);
              return Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: f.existsSync()
                      ? Image.file(f, fit: BoxFit.contain)
                      : const Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 64, color: Colors.grey)),
                ),
              );
            },
          ),
        ),
        if (_resolvedPaths.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                _resolvedPaths.length,
                (i) => Container(
                      width: i == _currentPage ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            i == _currentPage ? _kBlue : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
          ),
        if (_signatureBytes != null)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4EA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kGreen.withOpacity(0.3)),
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
                    ? Image.file(File(_resolvedPaths[i]), fit: BoxFit.cover)
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
              if (!widget.idMode) ...[
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.text_fields,
                    label: _isLoadingOcr ? 'A extrair...' : 'OCR',
                    loading: _isLoadingOcr,
                    color: _kBlue,
                    bg: const Color(0xFFE8F0FE),
                    onTap: _isLoadingOcr ? null : _runOCR,
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
                  border: Border.all(color: _kBlue.withOpacity(0.2)),
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
          border: Border.all(color: color.withOpacity(0.2), width: 0.5),
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
              ? const Color(0xFF1A73E8).withOpacity(0.1)
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
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: path != null && File(path!).existsSync()
            ? SfPdfViewer.file(
                File(path!),
                canShowScrollHead: false,
                canShowScrollStatus: false,
              )
            : Center(
                child: Icon(Icons.credit_card_outlined,
                    size: 48, color: Colors.grey.shade400),
              ),
      ),
    );
  }
}
