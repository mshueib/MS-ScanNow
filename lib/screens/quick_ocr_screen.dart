import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/ocr_service.dart';
import '../widgets/primary_button.dart';
import '../widgets/safe_bottom_panel.dart';

const _kBlue = Color(0xFF1A73E8);

/// "Extrair Texto" — acção standalone da Home: escolhe uma imagem (câmara
/// ou galeria) e corre o OCR já existente (`OCRService`), sem passar pelo
/// fluxo completo de digitalização/gerar PDF.
class QuickOcrScreen extends StatefulWidget {
  const QuickOcrScreen({super.key});
  @override
  State<QuickOcrScreen> createState() => _QuickOcrScreenState();
}

class _QuickOcrScreenState extends State<QuickOcrScreen> {
  final _picker = ImagePicker();
  String? _imagePath;
  bool _isLoading = false;
  String _text = '';

  Future<void> _pick(ImageSource source) async {
    try {
      final photo = await _picker.pickImage(source: source, imageQuality: 92);
      if (photo == null || !mounted) return;
      setState(() {
        _imagePath = photo.path;
        _text = '';
        _isLoading = true;
      });
      final text = await OCRService.extractText(photo.path);
      if (!mounted) return;
      setState(() {
        _text = text;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Erro OCR rápido: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível extrair texto desta imagem.')));
    }
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Texto copiado.'), behavior: SnackBarBehavior.floating));
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: _text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Não foi possível partilhar o texto.')));
    }
  }

  void _reset() => setState(() {
        _imagePath = null;
        _text = '';
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Extrair Texto'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_imagePath != null)
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Nova imagem',
                onPressed: _reset),
        ],
      ),
      body: _imagePath == null ? _buildPicker() : _buildResult(),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.text_fields, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Escolha uma imagem para extrair o texto',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF636366))),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Câmara'),
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
                  child: PrimaryButton(
                    onPressed: () => _pick(ImageSource.gallery),
                    color: _kBlue,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: 'Galeria',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(File(_imagePath!),
                height: 140, width: double.infinity, fit: BoxFit.cover),
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    child: SelectableText(_text,
                        style: const TextStyle(fontSize: 14, height: 1.6)),
                  ),
                ),
        ),
        if (!_isLoading && _text.isNotEmpty)
          SafeBottomPanel(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copiar'),
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
                  child: PrimaryButton(
                    onPressed: _share,
                    color: _kBlue,
                    icon: const Icon(Icons.share_outlined),
                    label: 'Partilhar',
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}
