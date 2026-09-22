import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import '../screens/document_editor_screen.dart';
import '../screens/pdf_viewer_screen.dart';
import '../services/storage_service.dart';
import 'document_thumbnail.dart';
import 'name_dialog.dart';
import 'safe_bottom_panel.dart';

const _kBlue = Color(0xFF1A73E8);

/// Abre um documento no ecrã apropriado. PDFs com mais de uma página (ex.:
/// resultado da ferramenta "Juntar") vão para o visualizador de PDF real
/// (`PDFViewerScreen`, já usado noutros pontos da app), que sabe navegar
/// entre páginas — ao contrário do editor de imagem única, que só mostra a
/// primeira imagem embutida. Documentos de página única e `bi_multi`
/// continuam a abrir no editor de sempre, sem qualquer alteração ao seu
/// comportamento.
void openDocument(BuildContext context, DocumentModel doc) {
  if (!File(doc.path).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ficheiro não encontrado — pode ter sido apagado.')));
    return;
  }
  if (doc.type == 'pdf' && doc.pageCount > 1) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PDFViewerScreen(path: doc.path)));
  } else {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => DocumentEditorScreen(doc: doc)));
  }
}

/// Mostra o menu de opções (abrir/partilhar/renomear/eliminar) para um
/// documento — usado tanto pela lista de Histórico como pelos "Recentes"
/// no ecrã Início, para que o botão de opções tenha sempre o mesmo comportamento.
void showDocumentOptions(BuildContext context, DocumentModel doc) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => _DocOptions(
      doc: doc,
      onDelete: () async {
        final confirmed = await _confirmDeleteDialog(context, doc);
        if (confirmed != true || !context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        try {
          await StorageService.deleteDocument(doc);
        } catch (_) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Não foi possível eliminar o documento.')));
        }
      },
    ),
  );
}

/// Abre o diálogo de renomear e grava o novo nome — reaproveitado tanto
/// pelo menu "···" como pelo toque direto no nome do documento (edição
/// inline), para que as duas entradas tenham exactamente o mesmo comportamento.
Future<void> renameDocument(BuildContext context, DocumentModel doc) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => NameDialog(title: 'Renomear documento', initialValue: doc.name),
  );
  if (name == null || name == doc.name || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    doc.name = name;
    await doc.save();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Não foi possível renomear o documento.')));
  }
}

Future<bool?> _confirmDeleteDialog(BuildContext context, DocumentModel doc) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminar documento'),
      content: Text(
          'Deseja eliminar "${doc.name}"?\nEsta acção não pode ser desfeita.'),
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

  Future<bool?> _confirmDelete(BuildContext context) =>
      _confirmDeleteDialog(context, document);

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(document.key),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) {
        final messenger = ScaffoldMessenger.of(context);
        StorageService.deleteDocument(document).catchError((_) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Não foi possível eliminar o documento.')));
        });
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFD93025).withValues(alpha: 0.1),
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
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: DocumentThumbnail(
            document: document,
            width: 40,
            height: 48,
            borderRadius: BorderRadius.circular(8),
          ),
          title: InkWell(
            onTap: () => renameDocument(context, document),
            child: Text(document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          subtitle: Text(
              '${_fmt(document.date)}'
              '${document.pageCount > 1 ? ' · ${document.pageCount} pág.' : ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA))),
          trailing: IconButton(
            icon:
                const Icon(Icons.more_vert, color: Color(0xFFCCCCCC), size: 20),
            onPressed: () => showDocumentOptions(context, document),
          ),
          onTap: () => openDocument(context, document),
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
    return SafeBottomPanel(
      child: Column(
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
              openDocument(context, doc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined, color: _kBlue),
            title: const Text('Partilhar'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                await SharePlus.instance.share(ShareParams(
                    files: [XFile(doc.path)], text: 'Documento do MS ScanNow'));
              } catch (_) {
                messenger.showSnackBar(const SnackBar(
                    content: Text('Não foi possível partilhar o documento.')));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline,
                color: Color(0xFF1E8E3E)),
            title: const Text('Renomear'),
            onTap: () {
              Navigator.pop(context);
              renameDocument(context, doc);
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
      ),
    );
  }
}
