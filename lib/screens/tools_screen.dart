import 'package:flutter/material.dart';
import 'pdf_tools_screen.dart';
import 'quick_ocr_screen.dart';
import 'scanner_screen.dart';
import 'signature_library_screen.dart';

const _kBlue = Color(0xFF1A73E8);
const _kBg = Color(0xFFF0F2F5);

/// Aba "Ferramentas" da navegação inferior — reúne os atalhos para
/// funcionalidades já existentes (OCR, BI/ID, Assinar) e o ecrã de
/// Juntar/Comprimir PDFs (Fase 6), sem duplicar lógica: cada cartão apenas
/// navega para o ecrã já implementado.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text('Ferramentas'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ToolRow(
            icon: Icons.merge_type,
            color: const Color(0xFF8E44AD),
            title: 'Juntar / Comprimir PDFs',
            subtitle: 'Combine ou reduza o tamanho de documentos.',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PdfToolsScreen())),
          ),
          const SizedBox(height: 10),
          _ToolRow(
            icon: Icons.text_fields,
            color: _kBlue,
            title: 'Extrair Texto',
            subtitle: 'OCR standalone a partir de uma imagem.',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QuickOcrScreen())),
          ),
          const SizedBox(height: 10),
          _ToolRow(
            icon: Icons.credit_card_outlined,
            color: const Color(0xFFF9AB00),
            title: 'Cartões de Identificação',
            subtitle: 'Digitalizar BI/ID (frente e verso).',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ScannerScreen(initialMode: ScanMode.id))),
          ),
          const SizedBox(height: 10),
          _ToolRow(
            icon: Icons.draw_outlined,
            color: const Color(0xFF1E8E3E),
            title: 'Assinar',
            subtitle: 'Biblioteca de assinaturas digitais.',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SignatureLibraryScreen())),
          ),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolRow({
    required this.icon,
    required this.color,
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
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color),
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
