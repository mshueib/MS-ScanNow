import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/document_model.dart';
import '../services/pdf_service.dart';

const _kBlue = Color(0xFF1A73E8);

/// Miniatura da primeira página de um documento — tenta
/// `PDFService.extractEmbeddedImage` (rápido, sem o alterar) e cai para
/// `PDFService.rasterizeFirstPage` (rasterização nativa) quando esse falha.
/// Cai para o ícone genérico em documentos combinados (`bi_multi`, que têm
/// duas imagens na mesma página) ou sempre que ambas as vias falharem.
class DocumentThumbnail extends StatefulWidget {
  final DocumentModel document;
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const DocumentThumbnail({
    super.key,
    required this.document,
    this.width = 34,
    this.height = 42,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  State<DocumentThumbnail> createState() => _DocumentThumbnailState();
}

class _DocumentThumbnailState extends State<DocumentThumbnail> {
  // Cache simples em memória — evita re-extrair a mesma imagem sempre que a
  // linha volta a entrar em ecrã numa lista com scroll.
  static final Map<String, Uint8List?> _cache = {};

  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DocumentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.path != widget.document.path) _load();
  }

  Future<void> _load() async {
    final path = widget.document.path;
    if (widget.document.type == 'bi_multi') return;
    if (_cache.containsKey(path)) {
      if (mounted) setState(() => _bytes = _cache[path]);
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      // Via rápida primeiro (bytes contíguos); só recorre à rasterização
      // nativa, mais lenta, quando falha — ex.: PDFs devolvidos
      // directamente pelo ML Kit nalguns Samsung, cuja imagem não está
      // guardada como JPEG/PNG contíguo.
      var img = await compute(PDFService.extractEmbeddedImage, bytes);
      img ??= await PDFService.rasterizeFirstPage(bytes);
      _cache[path] = img;
      if (!mounted) return;
      setState(() => _bytes = img);
    } catch (_) {
      // mantém o ícone de reserva
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Container(
        width: widget.width,
        height: widget.height,
        color: const Color(0xFFE8F0FE),
        alignment: Alignment.center,
        child: _bytes != null
            ? Image.memory(
                _bytes!,
                width: widget.width,
                height: widget.height,
                fit: BoxFit.cover,
                cacheWidth:
                    (widget.width * MediaQuery.devicePixelRatioOf(context))
                        .round(),
              )
            : Icon(Icons.picture_as_pdf,
                color: _kBlue, size: widget.width * 0.5),
      ),
    );
  }
}
