import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import '../services/storage_service.dart';

const _kBlue = Color(0xFF1A73E8);

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final box = Hive.box<DocumentModel>('documents');

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              color: _kBlue,
              padding: EdgeInsets.fromLTRB(20, top + 14, 20, 28),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 12),
                  const Text('Utilizador',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  // Estatísticas rápidas
                  ValueListenableBuilder(
                    valueListenable: box.listenable(),
                    builder: (_, Box<DocumentModel> b, __) => Text(
                      '${b.length} documento${b.length == 1 ? '' : 's'} guardado${b.length == 1 ? '' : 's'}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Estatísticas
            ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (_, Box<DocumentModel> b, __) {
                final docs = b.values.toList();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      _StatCard(
                        icon: Icons.description_outlined,
                        label: 'Documentos',
                        value: '${docs.length}',
                        color: _kBlue,
                        bg: const Color(0xFFE8F0FE),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        icon: Icons.calendar_today_outlined,
                        label: 'Este mês',
                        value: '${_thisMonth(docs)}',
                        color: const Color(0xFF1E8E3E),
                        bg: const Color(0xFFE6F4EA),
                      ),
                      const SizedBox(width: 10),
                      _StatCard(
                        icon: Icons.storage_outlined,
                        label: 'Tamanho',
                        value: _totalSize(docs),
                        color: const Color(0xFFF9AB00),
                        bg: const Color(0xFFFEF7E0),
                      ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 20),

            // Secção — Documentos
            const _SectionHeader(title: 'Os meus documentos'),
            ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (_, Box<DocumentModel> b, __) {
                final docs = b.values.toList().reversed.toList();
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open_outlined,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          const Text('Nenhum documento ainda.',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children:
                      docs.map((doc) => _ProfileDocRow(doc: doc)).toList(),
                );
              },
            ),

            const SizedBox(height: 20),

            // Secção — Acções
            const _SectionHeader(title: 'Acções'),
            _ActionTile(
              icon: Icons.share_outlined,
              label: 'Partilhar todos os documentos',
              color: _kBlue,
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final docs = box.values.toList();
                final files = docs
                    .where((d) => File(d.path).existsSync())
                    .map((d) => XFile(d.path))
                    .toList();
                if (files.isEmpty) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Nenhum documento para partilhar.')));
                  return;
                }
                try {
                  await SharePlus.instance
                      .share(ShareParams(files: files, text: 'Documentos do MS ScanNow'));
                } catch (_) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('Não foi possível partilhar os documentos.')));
                }
              },
            ),
            _ActionTile(
              icon: Icons.delete_sweep_outlined,
              label: 'Limpar todos os documentos',
              color: const Color(0xFFD93025),
              onTap: () => _confirmClearAll(context),
            ),
            _ActionTile(
              icon: Icons.info_outline,
              label: 'Sobre o MS ScanNow',
              color: const Color(0xFF636366),
              onTap: () => _showAbout(context),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  int _thisMonth(List<DocumentModel> docs) {
    final now = DateTime.now();
    return docs
        .where((d) => d.date.month == now.month && d.date.year == now.year)
        .length;
  }

  String _totalSize(List<DocumentModel> docs) {
    int bytes = 0;
    for (final doc in docs) {
      try {
        bytes += File(doc.path).lengthSync();
      } catch (_) {}
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _confirmClearAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar tudo'),
        content: const Text(
            'Todos os documentos serão eliminados permanentemente. Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await StorageService.deleteAll();
                navigator.pop();
                messenger.showSnackBar(const SnackBar(
                    content: Text('Todos os documentos eliminados.')));
              } catch (_) {
                navigator.pop();
                messenger.showSnackBar(const SnackBar(
                    content:
                        Text('Não foi possível eliminar todos os documentos.')));
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD93025)),
            child: const Text('Eliminar tudo'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'MS ScanNow',
      applicationVersion: '1.0.0',
      applicationIcon:
          const Icon(Icons.document_scanner, color: _kBlue, size: 40),
      children: const [
        Text('Scanner inteligente de documentos com OCR, PDF, '
            'assinatura digital e suporte a BI/ID.'),
      ],
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color, bg;
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color,
      required this.bg});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x12000000), width: 0.5),
        ),
        child: Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(value,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Color(0xFF999999))),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111))),
    );
  }
}

class _ProfileDocRow extends StatelessWidget {
  final DocumentModel doc;
  const _ProfileDocRow({required this.doc});

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

  @override
  Widget build(BuildContext context) {
    final date =
        '${doc.date.day} ${_months[doc.date.month - 1]} ${doc.date.year}';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12000000), width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 42,
            decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(6)),
            child: const Icon(Icons.picture_as_pdf, color: _kBlue, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(doc.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF111111))),
                Text('PDF · $date',
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFFAAAAAA))),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: _kBlue, size: 18),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              if (!File(doc.path).existsSync()) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Ficheiro não encontrado — pode ter sido apagado.')));
                return;
              }
              try {
                await SharePlus.instance.share(ShareParams(
                    files: [XFile(doc.path)],
                    text: 'Documento do MS ScanNow'));
              } catch (_) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Não foi possível partilhar o documento.')));
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12000000), width: 0.5),
      ),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        trailing:
            const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 18),
        onTap: onTap,
      ),
    );
  }
}
