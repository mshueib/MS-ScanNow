import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/saved_signature.dart';
import '../services/signature_library_service.dart';
import '../widgets/name_dialog.dart';
import 'signature_screen.dart';

const _kBlue = Color(0xFF1A73E8);
const _kGreen = Color(0xFF1E8E3E);
const _kRed = Color(0xFFD93025);

/// Ecrã "Assinar" do menu principal — gere as assinaturas guardadas para
/// reutilização, em vez de forçar a desenhar uma nova de cada vez que é
/// preciso assinar um documento.
class SignatureLibraryScreen extends StatefulWidget {
  const SignatureLibraryScreen({super.key});
  @override
  State<SignatureLibraryScreen> createState() => _SignatureLibraryScreenState();
}

class _SignatureLibraryScreenState extends State<SignatureLibraryScreen> {
  late List<SavedSignature> _saved = SignatureLibraryService.getAll();

  Future<void> _drawNew() async {
    final bytes = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => const SignatureScreen()),
    );
    if (bytes == null || !mounted) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => NameDialog(
        title: 'Nome da assinatura',
        initialValue: 'Assinatura ${_saved.length + 1}',
      ),
    );
    if (name == null || !mounted) return;
    await SignatureLibraryService.save(name, bytes);
    if (!mounted) return;
    setState(() => _saved = SignatureLibraryService.getAll());
  }

  Future<void> _delete(SavedSignature sig) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar assinatura'),
        content: Text('Deseja eliminar "${sig.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _kRed),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SignatureLibraryService.delete(sig);
    if (!mounted) return;
    setState(() => _saved = SignatureLibraryService.getAll());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Assinaturas'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
      ),
      body: _saved.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.draw_outlined,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    const Text('Nenhuma assinatura guardada.',
                        style: TextStyle(fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                        'Crie uma assinatura para a reutilizar em '
                        'qualquer documento, sem a desenhar de novo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: _saved.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemBuilder: (_, i) {
                final sig = _saved[i];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x12000000)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x08000000),
                          blurRadius: 6,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Expanded(
                          child: Image.memory(sig.bytes, fit: BoxFit.contain)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                              child: Text(sig.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500))),
                          GestureDetector(
                            onTap: () => _delete(sig),
                            child: const Icon(Icons.delete_outline,
                                size: 18, color: _kRed),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _drawNew,
        backgroundColor: _kGreen,
        icon: const Icon(Icons.add),
        label: const Text('Nova assinatura'),
      ),
    );
  }
}
