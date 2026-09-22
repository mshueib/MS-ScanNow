import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../models/document_model.dart';
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import '../widgets/draggable_signature.dart';
import '../widgets/primary_button.dart';
import '../widgets/safe_bottom_panel.dart';
import '../widgets/signature_picker.dart';
import 'pdf_viewer_screen.dart';

const _kBlue = Color(0xFF1A73E8);
const _kGreen = Color(0xFF1E8E3E);

/// Abre um documento já guardado no Histórico com as mesmas ferramentas do
/// fluxo de digitalização: extrair texto (OCR), colocar uma assinatura
/// (arrastável e redimensionável) e gravar as alterações no mesmo ficheiro.
class DocumentEditorScreen extends StatefulWidget {
  final DocumentModel doc;
  const DocumentEditorScreen({super.key, required this.doc});

  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends State<DocumentEditorScreen> {
  bool _loading = true;
  Uint8List? _imageBytes;

  String _ocrText = '';
  bool _isLoadingOcr = false;

  Uint8List? _signatureBytes;
  SignaturePlacement _placement = const SignaturePlacement();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// BI/ID gerado a partir de PDFs diretos (Samsung) desenha frente e verso
  /// como DUAS imagens separadas na mesma página — ao contrário de todos os
  /// outros documentos (uma só imagem por página). Para esses, extrair "a"
  /// imagem embedded só traria a primeira (a frente), perdendo o verso.
  bool get _isMultiImageDoc => widget.doc.type == 'bi_multi';

  Future<void> _load() async {
    if (_isMultiImageDoc) {
      setState(() => _loading = false);
      return;
    }
    try {
      final bytes = await File(widget.doc.path).readAsBytes();
      final img = await compute(PDFService.extractEmbeddedImage, bytes);
      if (!mounted) return;
      setState(() {
        _imageBytes = img;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String get _dateLabel {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  // ─── OCR ──────────────────────────────────────────────────────────────────

  Future<void> _runOcr() async {
    if (_imageBytes == null) return;
    setState(() {
      _isLoadingOcr = true;
      _ocrText = '';
    });
    File? tmp;
    try {
      tmp = await PDFService.writeTempImage(_imageBytes!);
      final text = await OCRService.extractText(tmp.path);
      if (!mounted) return;
      setState(() => _ocrText = text);
    } catch (e) {
      if (kDebugMode) debugPrint('Erro OCR (editor): $e');
      if (!mounted) return;
      _showSnack('Não foi possível extrair texto desta imagem.');
    } finally {
      if (tmp != null) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isLoadingOcr = false);
    }
  }

  // ─── Assinatura ───────────────────────────────────────────────────────────

  Future<void> _addSignature() async {
    final bytes = await pickSignature(context);
    if (bytes == null || !mounted) return;
    setState(() {
      _signatureBytes = bytes;
      _placement = const SignaturePlacement();
    });
  }

  // ─── Guardar alterações (sobrescreve o mesmo ficheiro) ────────────────────

  Future<void> _saveChanges() async {
    if (_imageBytes == null) return;
    setState(() => _isSaving = true);
    File? tmpFile;
    try {
      tmpFile = await PDFService.writeTempImage(_imageBytes!);

      RecognizedText? recognized;
      Size? origSize;
      try {
        recognized = await OCRService.recognize(tmpFile.path);
        origSize = await PDFService.decodeImageSize(_imageBytes!);
      } catch (e) {
        if (kDebugMode) debugPrint('OCR indisponível ao gravar: $e');
      }

      // Desenha a assinatura diretamente nos pixeis ANTES de comprimir —
      // garante que a pré-visualização (que mostra a imagem) e o PDF final
      // ficam sempre exatamente iguais.
      var baked = _imageBytes!;
      if (_signatureBytes != null) {
        try {
          baked = await PDFService.bakeSignatureOntoImage(
            baked,
            signatureBytes: _signatureBytes!,
            placement: _placement,
            dateLabel: _dateLabel,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('Erro ao aplicar assinatura: $e');
        }
      }
      final compressed = await compute(PDFService.compressBytes, baked);
      final image = pw.MemoryImage(compressed);

      final pdf = pw.Document();
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (ctx) {
          final aW = ctx.page.pageFormat.availableWidth;
          final aH = ctx.page.pageFormat.availableHeight;
          final imgW = (image.width ?? 1).toDouble();
          final imgH = (image.height ?? 1).toDouble();
          final rect = PDFService.containRect(aW, aH, imgW, imgH);
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
              ...PDFService.ocrOverlay(
                recognized,
                imageSize: origSize,
                drawX: rect.x,
                drawY: rect.y,
                drawW: rect.w,
                drawH: rect.h,
              ),
          ]);
        },
      ));

      final bytesOut = await pdf.save();
      await File(widget.doc.path).writeAsBytes(bytesOut);
      widget.doc.date = DateTime.now();
      await widget.doc.save();

      if (!mounted) return;
      setState(() {
        _imageBytes = compressed; // já com a assinatura aplicada
        _signatureBytes = null;
      });
      _showSnack('Alterações guardadas!');
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao gravar alterações: $e');
      if (!mounted) return;
      _showSnack('Não foi possível guardar as alterações.');
    } finally {
      if (tmpFile != null) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(
          files: [XFile(widget.doc.path)], text: 'Documento do MS ScanNow'));
    } catch (_) {
      _showSnack('Não foi possível partilhar o documento.');
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title:
            Text(widget.doc.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Partilhar',
              onPressed: _share),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _imageBytes == null
              ? _buildFallback()
              : Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final box = constraints.biggest;
                          return Container(
                            color: Colors.black12,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: Image.memory(_imageBytes!,
                                      fit: BoxFit.contain),
                                ),
                                if (_signatureBytes != null)
                                  ...buildDraggableSignatureWidgets(
                                    box: box,
                                    signatureBytes: _signatureBytes!,
                                    placement: _placement,
                                    dateLabel: _dateLabel,
                                    onPlacementChanged: (p) =>
                                        setState(() => _placement = p),
                                    onRemove: () =>
                                        setState(() => _signatureBytes = null),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    SafeBottomPanel(child: _buildActionPanel()),
                  ],
                ),
    );
  }

  Widget _buildFallback() {
    if (!File(widget.doc.path).existsSync()) {
      return const Center(child: Text('Ficheiro não encontrado.'));
    }
    if (_isMultiImageDoc) {
      // BI/ID com frente e verso já compostos na mesma página — mostra o
      // PDF real diretamente (o editor de imagem única só mostraria um
      // dos lados). Sem OCR/assinatura aqui — essa combinação já foi
      // feita ao gravar o BI/ID.
      return SfPdfViewer.file(
        File(widget.doc.path),
        onDocumentLoadFailed: (d) =>
            _showSnack('Erro ao abrir PDF: ${d.description}'),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PDFViewerScreen(path: widget.doc.path))),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.picture_as_pdf_outlined, size: 56, color: Colors.grey),
            SizedBox(height: 8),
            Text('Toque para ver o PDF'),
            SizedBox(height: 4),
            Text('OCR e assinatura indisponíveis neste ficheiro.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_signatureBytes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.open_with, size: 14, color: _kGreen),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Arraste e redimensione a assinatura',
                      style: TextStyle(fontSize: 11, color: _kGreen)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _placement = _placement.copyWith(
                      includeDate: !_placement.includeDate)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        _placement.includeDate
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 16,
                        color: _kGreen),
                    const SizedBox(width: 4),
                    const Text('Incluir data',
                        style: TextStyle(fontSize: 11, color: _kGreen)),
                  ]),
                ),
              ]),
            ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isLoadingOcr ? null : _runOcr,
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
                  side: BorderSide(color: _kBlue.withValues(alpha: 0.5)),
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
                    _signatureBytes != null ? Icons.draw : Icons.draw_outlined,
                    size: 18),
                label: Text(_signatureBytes != null ? 'Assinado' : 'Assinar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kGreen,
                  side: BorderSide(color: _kGreen.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
          if (_signatureBytes != null) ...[
            const SizedBox(height: 10),
            PrimaryButton(
              onPressed: _isSaving ? null : _saveChanges,
              color: _kBlue,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_alt),
              label: _isSaving ? 'A guardar...' : 'Guardar alterações',
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
    );
  }
}
