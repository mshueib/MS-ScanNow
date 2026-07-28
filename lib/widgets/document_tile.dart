import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import '../screens/pdf_viewer_screen.dart';
import '../services/storage_service.dart';

const _kBlue = Color(0xFF1A73E8);

class DocumentTile extends StatelessWidget {
  final DocumentModel document;
  const DocumentTile({super.key, required this.document});

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

  String _fmt(DateTime dt) => '${dt.day} ${_months[dt.month - 1]} ${dt.year} · '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar documento'),
        content: Text(
            'Deseja eliminar "${document.name}"?\nEsta acção não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _DocOptions(
        doc: document,
        onDelete: () async {
          final confirmed = await _confirmDelete(context);
          if (confirmed == true) {
            await StorageService.deleteDocument(document);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(document.key),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => StorageService.deleteDocument(document),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD93025).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Color(0xFFD93025)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x12000000), width: 0.5),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Container(
            width: 40,
            height: 48,
            decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.picture_as_pdf, color: _kBlue, size: 20),
          ),
          title: Text(document.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          subtitle: Text(_fmt(document.date),
              style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA))),
          trailing: IconButton(
            icon:
                const Icon(Icons.more_vert, color: Color(0xFFCCCCCC), size: 20),
            onPressed: () => _showOptions(context),
          ),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PDFViewerScreen(path: document.path))),
        ),
      ),
    );
  }
}

// ─── Bottom sheet de opções ───────────────────────────────────────────────────

class _DocOptions extends StatelessWidget {
  final DocumentModel doc;
  final VoidCallback onDelete;
  const _DocOptions({required this.doc, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(doc.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.open_in_new_outlined, color: _kBlue),
          title: const Text('Abrir'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PDFViewerScreen(path: doc.path)));
          },
        ),
        ListTile(
          leading: const Icon(Icons.share_outlined, color: _kBlue),
          title: const Text('Partilhar'),
          onTap: () async {
            Navigator.pop(context);
            await Share.shareXFiles([XFile(doc.path)],
                text: 'Documento do MS ScanNow');
          },
        ),
        ListTile(
          leading: const Icon(Icons.drive_file_rename_outline,
              color: Color(0xFF1E8E3E)),
          title: const Text('Renomear'),
          onTap: () {
            Navigator.pop(context);
            _renameDialog(context);
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Color(0xFFD93025)),
          title: const Text('Eliminar',
              style: TextStyle(color: Color(0xFFD93025))),
          onTap: () {
            Navigator.pop(context);
            onDelete();
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _renameDialog(BuildContext context) {
    final ctrl = TextEditingController(text: doc.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renomear documento'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome do documento'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                doc.name = name;
                doc.save();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
