import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/saved_signature.dart';
import '../screens/signature_screen.dart';
import '../services/signature_library_service.dart';
import 'name_dialog.dart';
import 'safe_bottom_panel.dart';

const _kGreen = Color(0xFF1E8E3E);
const _kRed = Color(0xFFD93025);

/// Mostra um seletor de assinatura — escolher uma já guardada ou desenhar
/// uma nova (com a opção de a guardar para reutilizar). Devolve os bytes
/// PNG escolhidos, ou `null` se cancelado.
Future<Uint8List?> pickSignature(BuildContext context) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => const _SignaturePickerSheet(),
  );
}

class _SignaturePickerSheet extends StatefulWidget {
  const _SignaturePickerSheet();
  @override
  State<_SignaturePickerSheet> createState() => _SignaturePickerSheetState();
}

class _SignaturePickerSheetState extends State<_SignaturePickerSheet> {
  late List<SavedSignature> _saved = SignatureLibraryService.getAll();

  Future<void> _drawNew() async {
    final navigator = Navigator.of(context);
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (bytes == null || !mounted) return;
    await _maybeSave(bytes);
    if (!mounted) return;
    navigator.pop(bytes);
  }

  Future<void> _maybeSave(Uint8List bytes) async {
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar assinatura'),
        content: const Text(
            'Queres guardar esta assinatura para a reutilizar noutros documentos?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Não guardar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (save != true || !mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Nome da assinatura',
        initialValue: 'Assinatura ${_saved.length + 1}',
      ),
    );
    if (name == null) return;
    await SignatureLibraryService.save(name, bytes);
  }

  Future<void> _delete(SavedSignature sig) async {
    await SignatureLibraryService.delete(sig);
    if (!mounted) return;
    setState(() => _saved = SignatureLibraryService.getAll());
  }

  @override
  Widget build(BuildContext context) {
    return SafeBottomPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const Text('Assinatura',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            if (_saved.isNotEmpty) ...[
              const Text('Guardadas',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: GridView.builder(
                  shrinkWrap: true,
                  itemCount: _saved.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.9,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, i) {
                    final sig = _saved[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, sig.bytes),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x1A000000)),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                                child: Image.memory(sig.bytes,
                                    fit: BoxFit.contain)),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(sig.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                                GestureDetector(
                                  onTap: () => _delete(sig),
                                  child: const Icon(Icons.close,
                                      size: 14, color: _kRed),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _drawNew,
                icon: const Icon(Icons.draw_outlined, size: 18),
                label: const Text('Nova assinatura'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kGreen,
                  side: BorderSide(color: _kGreen.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
