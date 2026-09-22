import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/document_model.dart';
import '../services/storage_service.dart';
import '../widgets/document_tile.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/safe_bottom_panel.dart';

const _kBlue = Color(0xFF1A73E8);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<DocumentModel> _selected = {};
  bool get _selecting => _selected.isNotEmpty;

  void _exitSelection() => setState(() => _selected.clear());

  Future<void> _deleteSelected() async {
    final docs = _selected.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar documentos'),
        content: Text(
            'Deseja eliminar ${docs.length} documento${docs.length == 1 ? '' : 's'}?\n'
            'Esta acção não pode ser desfeita.'),
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
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await StorageService.deleteMany(docs);
      if (mounted) _exitSelection();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível eliminar os documentos.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<DocumentModel>('documents');

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _selecting ? '${_selected.length} selecionado(s)' : 'Todos os Documentos'),
        centerTitle: true,
        leading: _selecting
            ? IconButton(icon: const Icon(Icons.close), onPressed: _exitSelection)
            : null,
        actions: _selecting
            ? [
                IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar selecionados',
                    onPressed: _deleteSelected),
              ]
            : [
                ValueListenableBuilder(
                  valueListenable: box.listenable(),
                  builder: (_, Box<DocumentModel> b, __) {
                    if (b.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.search),
                      tooltip: 'Pesquisar',
                      onPressed: () => showSearch(
                        context: context,
                        delegate: _DocumentSearchDelegate(b.values.toList()),
                      ),
                    );
                  },
                ),
              ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<DocumentModel> box, _) {
          final docs = box.values.toList().reversed.toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.folder_open_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nenhum documento ainda',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Escaneie um documento para começar.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.fromLTRB(
                0,
                8,
                0,
                8 +
                    MediaQuery.paddingOf(context).bottom +
                    SafeBottomPanel.extraInset(context)),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              if (_selecting) {
                return _SelectableRow(
                  document: doc,
                  checked: _selected.contains(doc),
                  onToggle: (v) => setState(() {
                    if (v) {
                      _selected.add(doc);
                    } else {
                      _selected.remove(doc);
                    }
                  }),
                );
              }
              return GestureDetector(
                onLongPress: () => setState(() => _selected.add(doc)),
                child: DocumentTile(document: doc),
              );
            },
          );
        },
      ),
    );
  }
}

/// Linha usada apenas no modo de seleção múltipla — toque alterna o
/// checkbox em vez de abrir o documento (evita conflito com o
/// comportamento normal do `DocumentTile`, que já usa o toque para abrir
/// e o swipe para eliminar individualmente).
class _SelectableRow extends StatelessWidget {
  final DocumentModel document;
  final bool checked;
  final ValueChanged<bool> onToggle;

  const _SelectableRow({
    required this.document,
    required this.checked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: checked ? const Color(0xFFE8F0FE) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: checked ? _kBlue.withValues(alpha: 0.4) : const Color(0x12000000),
            width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        onTap: () => onToggle(!checked),
        leading: Checkbox(
          value: checked,
          activeColor: _kBlue,
          onChanged: (v) => onToggle(v ?? false),
        ),
        title: Row(
          children: [
            DocumentThumbnail(
                document: document,
                width: 34,
                height: 42,
                borderRadius: BorderRadius.circular(6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(document.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentSearchDelegate extends SearchDelegate<DocumentModel?> {
  final List<DocumentModel> docs;

  _DocumentSearchDelegate(this.docs);

  @override
  String get searchFieldLabel => 'Buscar documentos...';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final results = docs
        .where((d) => d.name.toLowerCase().contains(query.toLowerCase()))
        .toList();

    if (results.isEmpty) {
      return Center(
        child: Text(
          'Nenhum resultado para "$query"',
          style: const TextStyle(fontSize: 15),
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) => DocumentTile(document: results[i]),
    );
  }
}
