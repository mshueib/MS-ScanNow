import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/document_model.dart';
import '../widgets/document_tile.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<DocumentModel>('documents');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico'),
        centerTitle: true,
        actions: [
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
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) =>
                DocumentTile(document: docs[index]),
          );
        },
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
