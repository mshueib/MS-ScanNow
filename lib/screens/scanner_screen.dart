import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'preview_screen.dart';

enum ScanMode { general, document, id }

extension ScanModeExt on ScanMode {
  String get label {
    switch (this) {
      case ScanMode.general:
        return 'Geral';
      case ScanMode.document:
        return 'Documento';
      case ScanMode.id:
        return 'BI / ID';
    }
  }

  String get hint {
    switch (this) {
      case ScanMode.general:
        return 'Capture qualquer conteúdo';
      case ScanMode.document:
        return 'Posicione o documento na área';
      case ScanMode.id:
        return 'Capture a frente do BI / ID';
    }
  }

  IconData get icon {
    switch (this) {
      case ScanMode.general:
        return Icons.photo_camera_outlined;
      case ScanMode.document:
        return Icons.description_outlined;
      case ScanMode.id:
        return Icons.credit_card_outlined;
    }
  }
}

class ScannerScreen extends StatefulWidget {
  final ScanMode initialMode;
  const ScannerScreen({super.key, this.initialMode = ScanMode.document});
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  late ScanMode _mode = widget.initialMode;
  bool _isCapturing = false;
  bool _mlKitFailed = false;

  final List<String> _pages = [];
  String? _idFront;
  String? _idBack;
  bool _idFrontIsPdf = false;
  bool _idBackIsPdf = false;
  // Qual lado a próxima captura no modo BI/ID deve preencher — definido
  // explicitamente ao tocar num dos slots "Frente"/"Verso", para que cada
  // toque abra a câmara diretamente para o lado certo (sem adivinhar).
  bool _idTargetFront = true;

  final _picker = ImagePicker();

  // ─── Permissão ────────────────────────────────────────────────────────────

  Future<bool> _checkPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return false;
    if (status.isPermanentlyDenied) {
      _showSnack('Permissão negada. Active nas definições.', action: true);
      return false;
    }
    if (!status.isGranted) {
      _showSnack('Permissão de câmera necessária.');
      return false;
    }
    return true;
  }

  // ─── Converter URI / path para ficheiro local acessível ───────────────────
  //
  // O ML Kit no dispositivo real devolve URIs do tipo content://...
  // O File() do Dart não consegue ler URIs directamente — precisamos copiar
  // o conteúdo para o directório da app primeiro.

  Future<String> _resolveToLocalPath(String uriOrPath) async {
    // Se já é um path absoluto de ficheiro, devolve directamente
    if (uriOrPath.startsWith('/')) return uriOrPath;

    // É uma URI (content:// ou file://) — copia para directório local
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.jpg';

    try {
      // Lê através do canal de plataforma (único modo seguro para content://)
      const channel = MethodChannel('plugins.flutter.io/image_picker');
      final data = await channel
          .invokeMethod<Uint8List>('retrieveImage', {'uri': uriOrPath});
      if (data != null) {
        await File(dest).writeAsBytes(data);
        return dest;
      }
    } catch (_) {}

    // Fallback: tenta como file URI
    try {
      final uri = Uri.parse(uriOrPath);
      if (uri.isScheme('file')) {
        return uri.toFilePath();
      }
    } catch (_) {}

    // Última tentativa: copiar com XFile
    try {
      final xfile = XFile(uriOrPath);
      await xfile.saveTo(dest);
      return dest;
    } catch (_) {}

    return uriOrPath; // devolve original se tudo falhar
  }

  Future<List<String>> _resolveAll(List<String> raw) async {
    final resolved = <String>[];
    for (final r in raw) {
      resolved.add(await _resolveToLocalPath(r));
    }
    return resolved;
  }

  // ─── Captura principal ────────────────────────────────────────────────────

  Future<void> _capture({bool? idFront}) async {
    if (_isCapturing) return;
    if (idFront != null) _idTargetFront = idFront;
    if (!await _checkPermission()) return;

    setState(() => _isCapturing = true);
    try {
      if (_mlKitFailed) {
        await _captureWithImagePicker();
      } else {
        await _captureWithMlKit();
      }
    } catch (e) {
      if (mounted) _showSnack('Erro ao capturar. Tente novamente.');
      if (kDebugMode) debugPrint('Scanner error: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ─── ML Kit ───────────────────────────────────────────────────────────────

  Future<void> _captureWithMlKit() async {
    try {
      final int pageLimit = _mode == ScanMode.id
          ? 1
          : _mode == ScanMode.general
              ? 20
              : 10;

      // Usa dynamic para evitar cast errors — o pacote pode devolver
      // List, Map ou outro tipo dependendo da versão
      dynamic raw;
      try {
        raw = await FlutterDocScanner().getScanDocuments(page: pageLimit);
      } catch (_) {
        raw = await FlutterDocScanner()
            .getScannedDocumentAsImages(page: pageLimit);
      }

      if (!mounted) return;
      if (raw == null) return; // utilizador cancelou

      if (kDebugMode) {
        debugPrint('ML Kit raw result type: ${raw.runtimeType} — $raw');
      }

      final List<String> paths = _extractPaths(raw);
      if (kDebugMode) debugPrint('ML Kit paths extracted: $paths');

      if (paths.isEmpty) return;

      // Caso especial: ML Kit devolveu um PDF directamente (Samsung)
      if (paths.length == 1 && paths.first.startsWith('PDF:')) {
        final pdfPath = paths.first.substring(4); // remove prefixo 'PDF:'
        final localPdf = await _copyPdfToLocal(pdfPath);
        if (!mounted) return;
        // Vai directamente para o PreviewScreen em modo PDF
        _navigateToPdfPreview(localPdf);
        return;
      }

      final local = await _resolveAll(paths);
      if (!mounted) return;
      _addResults(local);
    } catch (e) {
      if (kDebugMode) debugPrint('ML Kit falhou: $e');
      if (mounted) {
        setState(() => _mlKitFailed = true);
        _showSnack('Scanner avançado indisponível. A usar câmera normal.');
        await _captureWithImagePicker();
      }
    }
  }

  /// Extrai paths do resultado do ML Kit.
  /// Samsung devolve: {pdfUri: 'file://...pdf', pageCount: 1}
  /// Outros dispositivos devolvem List<String> de imagens JPEG.
  /// Quando é PDF, marcamos com prefixo 'PDF:' para tratamento especial.
  List<String> _extractPaths(dynamic raw) {
    if (raw == null) return [];

    // Caso 1: List de imagens (formato antigo / outros dispositivos)
    if (raw is List) {
      return raw
          .where((e) => e != null)
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    // Caso 2: Map — Samsung e versões recentes devolvem Map
    if (raw is Map) {
      // Samsung devolve {pdfUri: '...', pageCount: N} — PDF directo
      final pdfUri = raw['pdfUri'] ?? raw['PDFUri'] ?? raw['pdf_uri'];
      if (pdfUri != null && pdfUri.toString().isNotEmpty) {
        return ['PDF:${pdfUri.toString()}'];
      }

      // Formato com lista de imagens
      for (final key in ['images', 'Images', 'Uri', 'uri', 'paths', 'Paths']) {
        final val = raw[key];
        if (val is List && val.isNotEmpty) {
          return val
              .where((e) => e != null)
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
        if (val is String && val.isNotEmpty) return [val];
      }

      // Último recurso: qualquer valor String ou List no Map
      for (final val in raw.values) {
        if (val is List && val.isNotEmpty) {
          return val
              .where((e) => e != null)
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList();
        }
        if (val is String &&
            val.isNotEmpty &&
            !val.toString().contains('pageCount') &&
            int.tryParse(val.toString()) == null) {
          return [val];
        }
      }
    }

    if (raw is String && raw.isNotEmpty) return [raw];
    return [];
  }

  // ─── Fallback: image_picker ───────────────────────────────────────────────

  Future<void> _captureWithImagePicker() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (!mounted || photo == null) return;
    _addResults([photo.path]);
  }

  // ─── Galeria ──────────────────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      if (_mode == ScanMode.id) {
        final photo = await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 92);
        if (!mounted || photo == null) return;
        _addResults([photo.path]);
      } else {
        final photos = await _picker.pickMultiImage(imageQuality: 92);
        if (!mounted || photos.isEmpty) return;
        _addResults(photos.map((f) => f.path).toList());
      }
    } catch (e) {
      if (mounted) _showSnack('Não foi possível abrir a galeria.');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ─── PDF directo do ML Kit ───────────────────────────────────────────────

  /// Copia o PDF da cache do ML Kit para o diretório permanente da app
  Future<String> _copyPdfToLocal(String uriOrPath) async {
    final dir = await getApplicationDocumentsDirectory();
    final dest =
        '${dir.path}/scan_${DateTime.now().millisecondsSinceEpoch}.pdf';
    try {
      String sourcePath = uriOrPath;
      if (uriOrPath.startsWith('file://')) {
        sourcePath = Uri.parse(uriOrPath).toFilePath();
      }
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        await sourceFile.copy(dest);
        return dest;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao copiar PDF: $e');
    }
    return uriOrPath;
  }

  /// Navega para PreviewScreen quando o ML Kit devolve PDF directamente
  void _navigateToPdfPreview(String pdfPath) {
    if (!mounted) return;
    if (_mode == ScanMode.id) {
      setState(() {
        if (_idTargetFront) {
          _idFront = pdfPath;
          _idFrontIsPdf = true;
          _showSnack(_idBack == null
              ? 'Frente capturada! Toque no verso para continuar.'
              : 'Frente atualizada.');
        } else {
          _idBack = pdfPath;
          _idBackIsPdf = true;
          _showSnack('Verso capturado! Toque em "Usar" para continuar.');
        }
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            paths: [pdfPath],
            isPdfDirect: true,
          ),
        ),
      );
    }
  }

  // ─── Adicionar resultados ─────────────────────────────────────────────────

  void _addResults(List<String> paths) {
    if (!mounted || paths.isEmpty) return;

    if (_mode == ScanMode.id) {
      setState(() {
        if (_idTargetFront) {
          _idFront = paths.first;
          _idFrontIsPdf = false;
          _showSnack(_idBack == null
              ? 'Frente capturada! Toque no verso para continuar.'
              : 'Frente atualizada.');
        } else {
          _idBack = paths.first;
          _idBackIsPdf = false;
          _showSnack('Verso capturado! Toque em "Usar" para continuar.');
        }
      });
    } else {
      setState(() => _pages.addAll(paths));
    }
  }

  // ─── Finalizar ────────────────────────────────────────────────────────────

  bool get _canFinalize =>
      _mode == ScanMode.id ? _idFront != null : _pages.isNotEmpty;

  void _finalize() {
    if (!_canFinalize) return;

    if (_mode == ScanMode.id) {
      final paths = [
        if (_idFront != null) _idFront!,
        if (_idBack != null) _idBack!,
      ];
      // No Samsung, os scans BI são PDFs — vai para preview especial
      final hasPdfs = _idFrontIsPdf || _idBackIsPdf;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            paths: paths,
            idMode: true,
            isPdfDirect: hasPdfs,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(
            paths: List<String>.from(_pages),
            idMode: false,
          ),
        ),
      );
    }
  }

  void _resetId() => setState(() {
        _idFront = null;
        _idBack = null;
        _idFrontIsPdf = false;
        _idBackIsPdf = false;
        _idTargetFront = true;
      });
  void _removePage(int i) => setState(() => _pages.removeAt(i));

  void _showSnack(String msg, {bool action = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      action: action
          ? const SnackBarAction(
              label: 'Definições', onPressed: openAppSettings)
          : null,
    ));
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildModeSelector(),
            Expanded(child: _buildViewfinder()),
            if (_mode == ScanMode.id) _buildIdSlots(),
            if (_mode != ScanMode.id && _pages.isNotEmpty)
              _buildThumbnailStrip(),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('MS ScanNow',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w500)),
                if (_mlKitFailed)
                  const Text('modo câmera básica',
                      style: TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: ScanMode.values.map((m) {
          final active = m == _mode;
          return GestureDetector(
            onTap: () => setState(() {
              _mode = m;
              _pages.clear();
              _idFront = null;
              _idBack = null;
              _idFrontIsPdf = false;
              _idBackIsPdf = false;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF1A73E8)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active
                      ? const Color(0xFF1A73E8)
                      : Colors.white.withValues(alpha: 0.15),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(m.icon,
                      size: 14, color: active ? Colors.white : Colors.white54),
                  const SizedBox(width: 5),
                  Text(m.label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: active ? Colors.white : Colors.white54)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildViewfinder() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(color: const Color(0xFF1A1A1A)),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _mode == ScanMode.id ? 20 : 32,
              vertical: _mode == ScanMode.id ? 40 : 24,
            ),
            child: _CornerFrame(
              color: const Color(0xFF1A73E8),
              aspectRatio: _mode == ScanMode.id ? 1.585 : 0.707,
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_mode.icon,
                size: 48, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              _mode == ScanMode.id
                  ? (_idFront == null
                      ? 'Toque para capturar a frente'
                      : _idBack == null
                          ? 'Agora capture o verso'
                          : 'Frente e verso prontos! Toque em "Usar"')
                  : _pages.isEmpty
                      ? 'Toque no botão para escanear'
                      : '${_pages.length} página(s) — toque em "Usar"',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                  height: 1.5),
            ),
          ],
        ),
        const Positioned(left: 40, right: 40, top: 60, child: _ScanLine()),
        if (_pages.isNotEmpty || _idFront != null)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _mode == ScanMode.id
                    ? '${(_idFront != null ? 1 : 0) + (_idBack != null ? 1 : 0)}/2 lados'
                    : '${_pages.length} pág.',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIdSlots() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('BI / ID — frente e verso',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const Spacer(),
            if (_idFront != null || _idBack != null)
              GestureDetector(
                onTap: _resetId,
                child: const Text('Recomeçar',
                    style: TextStyle(color: Color(0xFF1A73E8), fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _IdSlot(
                label: 'Frente',
                path: _idFront,
                captured: _idFront != null,
                onTap: _isCapturing ? () {} : () => _capture(idFront: true),
                locked: false), // frente nunca fica bloqueada
            const SizedBox(width: 10),
            _IdSlot(
                label: 'Verso',
                path: _idBack,
                captured: _idBack != null,
                onTap: _isCapturing ? () {} : () => _capture(idFront: false),
                locked:
                    false), // verso também não bloqueia — apenas indica estado
          ]),
          const SizedBox(height: 6),
          Text(
            _idFront == null
                ? 'Capture a frente primeiro'
                : _idBack == null
                    ? 'Capture o verso (opcional)'
                    : 'Ambos os lados prontos — toque em "Usar"',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStrip() {
    // Miniatura mostrada a 46x62 lógicos — não faz sentido descodificar a
    // imagem à resolução total da câmara só para isto.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (46 * dpr).round();
    final cacheH = (62 * dpr).round();
    return Container(
      color: Colors.black,
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(File(_pages[i]),
                  width: 46,
                  height: 62,
                  fit: BoxFit.cover,
                  cacheWidth: cacheW,
                  cacheHeight: cacheH),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                onTap: () => _removePage(i),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, color: Colors.white, size: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Usar
          GestureDetector(
            onTap: _canFinalize ? _finalize : null,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _canFinalize
                    ? const Color(0xFF1A73E8).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _canFinalize
                      ? const Color(0xFF1A73E8)
                      : Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check,
                      color: _canFinalize
                          ? const Color(0xFF1A73E8)
                          : Colors.white24,
                      size: 20),
                  Text('Usar',
                      style: TextStyle(
                          color: _canFinalize
                              ? const Color(0xFF1A73E8)
                              : Colors.white24,
                          fontSize: 10)),
                ],
              ),
            ),
          ),

          // Botão captura — no modo BI/ID, preenche o próximo lado em falta
          // (frente primeiro, depois verso), tal como tocar num slot faria.
          GestureDetector(
            onTap: _isCapturing
                ? null
                : () => _capture(
                    idFront: _mode == ScanMode.id ? _idFront == null : null),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isCapturing ? Colors.grey : Colors.white,
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3), width: 4),
              ),
              child: _isCapturing
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : null,
            ),
          ),

          // Galeria
          GestureDetector(
            onTap: _isCapturing ? null : _pickFromGallery,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1), width: 1),
              ),
              child: const Icon(Icons.photo_library_outlined,
                  color: Colors.white60, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _CornerFrame extends StatelessWidget {
  final Color color;
  final double aspectRatio;
  const _CornerFrame({required this.color, required this.aspectRatio});
  @override
  Widget build(BuildContext context) => AspectRatio(
      aspectRatio: aspectRatio,
      child: CustomPaint(painter: _CornerPainter(color)));
}

class _CornerPainter extends CustomPainter {
  final Color color;
  _CornerPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 28.0;
    final w = size.width, h = size.height;
    canvas.drawLine(const Offset(0, l), Offset.zero, p);
    canvas.drawLine(Offset.zero, const Offset(l, 0), p);
    canvas.drawLine(Offset(w - l, 0), Offset(w, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, l), p);
    canvas.drawLine(Offset(0, h - l), Offset(0, h), p);
    canvas.drawLine(Offset(0, h), Offset(l, h), p);
    canvas.drawLine(Offset(w - l, h), Offset(w, h), p);
    canvas.drawLine(Offset(w, h - l), Offset(w, h), p);
  }

  @override
  bool shouldRepaint(_CornerPainter o) => o.color != color;
}

class _ScanLine extends StatefulWidget {
  const _ScanLine();
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Transform.translate(
          offset: Offset(0, _anim.value * 160),
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.transparent,
                const Color(0xFF1A73E8).withValues(alpha: 0.8),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      );
}

class _IdSlot extends StatelessWidget {
  final String label;
  final String? path;
  final bool captured;
  final bool locked;
  final VoidCallback onTap;
  const _IdSlot(
      {required this.label,
      required this.path,
      required this.captured,
      required this.onTap,
      this.locked = false});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: captured
                ? const Color(0xFF1A73E8).withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: captured
                  ? const Color(0xFF1A73E8)
                  : Colors.white.withValues(alpha: 0.2),
              width: captured ? 1.5 : 1,
            ),
          ),
          child: path != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  // PDFs não podem ser renderizados com Image.file — mostrar ícone
                  child: path!.toLowerCase().endsWith('.pdf')
                      ? Container(
                          color:
                              const Color(0xFF1A73E8).withValues(alpha: 0.08),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.picture_as_pdf,
                                  color: Color(0xFF1A73E8), size: 28),
                              const SizedBox(height: 4),
                              Text('$label ✓',
                                  style: const TextStyle(
                                      color: Color(0xFF1A73E8),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        )
                      : Stack(fit: StackFit.expand, children: [
                          Image.file(
                            File(path!),
                            fit: BoxFit.cover,
                            // Slot pequeno (~metade da largura do ecrã, 68px
                            // de altura) — não precisa da imagem à resolução
                            // total da câmara.
                            cacheWidth: (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context) /
                                    2)
                                .round(),
                          ),
                          Positioned(
                            bottom: 4,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text('$label ✓',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10)),
                              ),
                            ),
                          ),
                        ]))
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.credit_card_outlined,
                        color: Colors.white30, size: 22),
                    const SizedBox(height: 4),
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
        ),
      ),
    );
  }
}
