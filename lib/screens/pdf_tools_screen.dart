import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/document_model.dart';
import '../services/pdf_service.dart';
import '../services/storage_service.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/primary_button.dart';
import '../widgets/safe_bottom_panel.dart';
import 'history_screen.dart';

const _kBlue = Color(0xFF1A73E8);

/// "Ferramentas PDF" — Juntar e Comprimir documentos já guardados no
/// Histórico. Reaproveita `PDFService.extractEmbeddedImage` e
/// `PDFService.createPdf` (ambos existentes, não alterados); a única
/// adição ao serviço foi `compressBytesStrong`, um método novo e
/// independente. Documentos `bi_multi` (frente+verso combinados) ficam de
/// fora — a extração de imagem única não se aplica a eles.
class PdfToolsScreen extends StatefulWidget {
  const PdfToolsScreen({super.key});
  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

enum _Mode { none, merge, compress }

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  _Mode _mode = _Mode.none;
  final Set<DocumentModel> _selected = {};
  bool _busy = false;

  List<DocumentModel> _eligibleDocs() {
    final box = Hive.box<DocumentModel>('documents');
    return box.values
        .where((d) => d.type != 'bi_multi' && File(d.path).existsSync())
        .toList()
        .reversed
        .toList();
  }

  void _enterMode(_Mode mode) {
    setState(() {
      _mode = mode;
      _selected.clear();
    });
  }

  void _cancel() => setState(() {
        _mode = _Mode.none;
        _selected.clear();
      });

  Future<void> _confirm() async {
    if (_mode == _Mode.merge) {
      await _runMerge();
    } else if (_mode == _Mode.compress) {
      await _runCompress();
    }
  }

  /// Extrai a imagem de um documento já guardado — tenta primeiro a via
  /// rápida (procura por bytes JPEG/PNG contíguos, funciona para os PDFs
  /// gerados por este app) e só recorre à rasterização nativa, mais lenta,
  /// quando essa falha (ex.: PDFs devolvidos diretamente pelo ML Kit nalguns
  /// Samsung, ou PDFs importados de terceiros, cuja imagem não está
  /// guardada como bytes contíguos).
  Future<Uint8List?> _extractImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final fast = await compute(PDFService.extractEmbeddedImage, bytes);
    if (fast != null) return fast;
    return PDFService.rasterizeFirstPage(bytes);
  }

  Future<void> _runMerge() async {
    final docs = _selected.toList();
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tempPaths = <String>[];
      for (final doc in docs) {
        final img = await _extractImage(doc.path);
        if (img == null) continue;
        final temp = await PDFService.writeTempImage(img);
        tempPaths.add(temp.path);
      }
      if (tempPaths.length < 2) {
        throw Exception('Imagens insuficientes para juntar.');
      }
      final file = await PDFService.createPdf(tempPaths);
      await StorageService.saveDocument(DocumentModel(
        name: 'Documento unido ${_timestamp()}',
        path: file.path,
        type: 'pdf',
        date: DateTime.now(),
        pageCount: tempPaths.length,
      ));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _mode = _Mode.none;
        _selected.clear();
      });
      messenger.showSnackBar(const SnackBar(
          content: Text('Documentos juntos com sucesso.'),
          behavior: SnackBarBehavior.floating));
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
    } catch (e, st) {
      if (kDebugMode) debugPrint('Erro ao juntar PDFs: $e\n$st');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível juntar estes documentos.')));
    }
  }

  Future<void> _runCompress() async {
    final doc = _selected.first;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final img = await _extractImage(doc.path);
      if (img == null) throw Exception('Sem imagem extraível.');
      final compressed = await compute(PDFService.compressBytesStrong, img);
      final temp = await PDFService.writeTempImage(compressed);
      final file = await PDFService.createPdf([temp.path]);
      await StorageService.saveDocument(DocumentModel(
        name: '${doc.name} (comprimido)',
        path: file.path,
        type: 'pdf',
        date: DateTime.now(),
        pageCount: 1,
      ));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _mode = _Mode.none;
        _selected.clear();
      });
      messenger.showSnackBar(const SnackBar(
          content: Text('Documento comprimido com sucesso.'),
          behavior: SnackBarBehavior.floating));
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
    } catch (e, st) {
      if (kDebugMode) debugPrint('Erro ao comprimir PDF: $e\n$st');
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível comprimir este documento.')));
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}-'
        '${now.month.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: Text(_mode == _Mode.none ? 'Ferramentas PDF' : 'Escolher documentos'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        leading: _mode == _Mode.none
            ? null
            : IconButton(icon: const Icon(Icons.close), onPressed: _cancel),
      ),
      body: _mode == _Mode.none ? _buildMenu() : _buildPicker(),
    );
  }

  Widget _buildMenu() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ToolCard(
          icon: Icons.merge_type,
          title: 'Juntar documentos',
          subtitle: 'Combina 2 ou mais documentos num único PDF.',
          onTap: () => _enterMode(_Mode.merge),
        ),
        const SizedBox(height: 12),
        _ToolCard(
          icon: Icons.compress,
          title: 'Comprimir documento',
          subtitle: 'Reduz o tamanho do ficheiro de um documento.',
          onTap: () => _enterMode(_Mode.compress),
        ),
      ],
    );
  }

  Widget _buildPicker() {
    final docs = _eligibleDocs();
    final isMerge = _mode == _Mode.merge;
    final canConfirm =
        isMerge ? _selected.length >= 2 : _selected.length == 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            isMerge
                ? 'Selecione 2 ou mais documentos para juntar.'
                : 'Selecione um documento para comprimir.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF636366)),
          ),
        ),
        Expanded(
          child: docs.isEmpty
              ? const Center(
                  child: Text('Nenhum documento disponível.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF999999))))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final doc = docs[i];
                    final checked = _selected.contains(doc);
                    return CheckboxListTile(
                      value: checked,
                      activeColor: _kBlue,
                      controlAffinity: ListTileControlAffinity.leading,
                      secondary: DocumentThumbnail(
                          document: doc,
                          width: 34,
                          height: 42,
                          borderRadius: BorderRadius.circular(6)),
                      title: Text(doc.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onChanged: (v) {
                        setState(() {
                          if (isMerge) {
                            if (v == true) {
                              _selected.add(doc);
                            } else {
                              _selected.remove(doc);
                            }
                          } else {
                            _selected
                              ..clear()
                              ..addAll(v == true ? [doc] : []);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
        SafeBottomPanel(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: PrimaryButton(
              onPressed: _busy || !canConfirm ? null : _confirm,
              color: _kBlue,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: isMerge ? 'Juntar' : 'Comprimir',
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: _kBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF888888))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC)),
            ],
          ),
        ),
      ),
    );
  }
}
