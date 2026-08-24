import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/document_model.dart';
import 'scanner_screen.dart';
import 'history_screen.dart';
import 'pdf_viewer_screen.dart';
import 'signature_screen.dart';
import 'profile_screen.dart';

const _kBlue = Color(0xFF1A73E8);
const _kBg = Color(0xFFF0F2F5);
const _kCard = Colors.white;
const _kBorder = Color(0x12000000);

// ─── Raiz ─────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 0 = Início · 1 = Docs/Recentes (Histórico) · 2 = Perfil
  int _tab = 0;

  void _onNav(int i) => setState(() => _tab = i);

  void _openScanner() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
  }

  static const _tabs = [_HomeTab(), HistoryScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: IndexedStack(
        index: _tab.clamp(0, _tabs.length - 1),
        children: _tabs,
      ),
      bottomNavigationBar:
          _BottomNav(current: _tab, onTap: _onNav, onScan: _openScanner),
    );
  }
}

// ─── Tab Início ───────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _Header(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(14, 16, 14, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _QuickActions(),
                  SizedBox(height: 20),
                  _ToolGrid(),
                  SizedBox(height: 20),
                  _RecentDocs(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Header com pesquisa funcional ───────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _kBlue,
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MS ScanNow',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3)),
                    SizedBox(height: 2),
                    Text('Scan · PDF · OCR · Assinatura',
                        style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
              CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white24,
                child:
                    Icon(Icons.person_outline, color: Colors.white, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Barra de pesquisa — abre SearchDelegate ao tocar
          GestureDetector(
            onTap: () {
              final box = Hive.box<DocumentModel>('documents');
              showSearch(
                context: context,
                delegate: _HomeSearchDelegate(box.values.toList()),
              );
            },
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 12),
                  Icon(Icons.search, color: Colors.white60, size: 17),
                  SizedBox(width: 8),
                  Text('Pesquisar documentos...',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── SearchDelegate para a barra de pesquisa ─────────────────────────────────

class _HomeSearchDelegate extends SearchDelegate<DocumentModel?> {
  final List<DocumentModel> docs;
  _HomeSearchDelegate(this.docs);

  @override
  String get searchFieldLabel => 'Pesquisar documentos...';

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _list(context);
  @override
  Widget buildSuggestions(BuildContext context) => _list(context);

  Widget _list(BuildContext context) {
    final results = query.isEmpty
        ? docs
        : docs
            .where((d) => d.name.toLowerCase().contains(query.toLowerCase()))
            .toList();

    if (results.isEmpty) {
      return Center(
          child: Text('Nenhum resultado para "$query"',
              style: const TextStyle(fontSize: 15)));
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (_, i) {
        final doc = results[i];
        return ListTile(
          leading: const Icon(Icons.picture_as_pdf, color: _kBlue),
          title: Text(doc.name),
          subtitle: Text('${doc.date.day}/${doc.date.month}/${doc.date.year}',
              style: const TextStyle(fontSize: 12)),
          onTap: () {
            close(context, doc);
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PDFViewerScreen(path: doc.path)));
          },
        );
      },
    );
  }
}

// ─── Acções rápidas ───────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  static const _items = [
    _QItem(
        'Scanner', Icons.document_scanner_outlined, _kBlue, Color(0xFFE8F0FE)),
    _QItem(
        'Assinar', Icons.draw_outlined, Color(0xFF1E8E3E), Color(0xFFE6F4EA)),
    _QItem('Histórico', Icons.history, Color(0xFFF9AB00), Color(0xFFFEF7E0)),
    _QItem('Partilhar', Icons.share_outlined, Color(0xFFD93025),
        Color(0xFFFCE8E6)),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_items.length, (i) {
        final item = _items[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < _items.length - 1 ? 8 : 0),
            child: _QuickCard(
                item: item, onTap: () => _onTap(context, item.label)),
          ),
        );
      }),
    );
  }

  void _onTap(BuildContext context, String label) {
    switch (label) {
      case 'Scanner':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
        break;
      case 'Assinar':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SignatureScreen()));
        break;
      case 'Histórico':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
        break;
      case 'Partilhar':
        // Partilha o último documento guardado
        final box = Hive.box<DocumentModel>('documents');
        if (box.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nenhum documento para partilhar.'),
            behavior: SnackBarBehavior.floating,
          ));
          return;
        }
        // Abre lista para escolher qual documento partilhar
        final docs = box.values.toList().reversed.toList();
        _showSharePicker(context, docs);
        break;
    }
  }

  void _showSharePicker(BuildContext context, List<DocumentModel> docs) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _SharePicker(docs: docs),
    );
  }
}

class _SharePicker extends StatelessWidget {
  final List<DocumentModel> docs;
  const _SharePicker({required this.docs});

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
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Escolher documento',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final date =
                  '${doc.date.day} ${_months[doc.date.month - 1]} ${doc.date.year}';
              return ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: _kBlue),
                title: Text(doc.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(date, style: const TextStyle(fontSize: 12)),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(ctx);
                  if (!File(doc.path).existsSync()) {
                    messenger.showSnackBar(const SnackBar(
                        content: Text(
                            'Ficheiro não encontrado — pode ter sido apagado.')));
                    return;
                  }
                  try {
                    await SharePlus.instance.share(ShareParams(
                        files: [XFile(doc.path)],
                        text: 'Documento digitalizado com MS ScanNow'));
                  } catch (_) {
                    messenger.showSnackBar(const SnackBar(
                        content:
                            Text('Não foi possível partilhar o documento.')));
                  }
                },
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _QItem {
  final String label;
  final IconData icon;
  final Color color, bg;
  const _QItem(this.label, this.icon, this.color, this.bg);
}

class _QuickCard extends StatelessWidget {
  final _QItem item;
  final VoidCallback onTap;
  const _QuickCard({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kBorder, width: 0.5),
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: item.bg, borderRadius: BorderRadius.circular(12)),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(item.label,
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF222222))),
          ],
        ),
      ),
    );
  }
}

// ─── Grelha de ferramentas ────────────────────────────────────────────────────

class _ToolGrid extends StatelessWidget {
  const _ToolGrid();

  static const _tools = [
    _TItem(
        'OCR', 'Extrair texto', Icons.text_fields, _kBlue, Color(0xFFE8F0FE)),
    _TItem('Criar PDF', 'Converter imagens', Icons.picture_as_pdf,
        Color(0xFFD93025), Color(0xFFFCE8E6)),
    _TItem('Organizar', 'Gerir documentos', Icons.folder_outlined,
        Color(0xFF1E8E3E), Color(0xFFE6F4EA)),
    _TItem('BI / ID', 'Frente e verso', Icons.credit_card_outlined,
        Color(0xFFF9AB00), Color(0xFFFEF7E0)),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ferramentas',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111))),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.9,
          children: _tools
              .map((t) =>
                  _ToolCard(item: t, onTap: () => _onTap(context, t.label)))
              .toList(),
        ),
      ],
    );
  }

  void _onTap(BuildContext context, String label) {
    switch (label) {
      case 'OCR':
        // Vai ao scanner — o OCR está disponível no PreviewScreen
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
        break;
      case 'Criar PDF':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
        break;
      case 'BI / ID':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ScannerScreen(initialMode: ScanMode.id)));
        break;
      case 'Organizar':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
        break;
    }
  }
}

class _TItem {
  final String label, desc;
  final IconData icon;
  final Color color, bg;
  const _TItem(this.label, this.desc, this.icon, this.color, this.bg);
}

class _ToolCard extends StatelessWidget {
  final _TItem item;
  final VoidCallback onTap;
  const _ToolCard({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: item.bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(item.icon, color: item.color, size: 17),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF111111))),
                  Text(item.desc,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF999999))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Documentos recentes ──────────────────────────────────────────────────────

class _RecentDocs extends StatelessWidget {
  const _RecentDocs();

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

  String _fmt(DateTime dt) => '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<DocumentModel>('documents');
    return ValueListenableBuilder(
      valueListenable: box.listenable(),
      builder: (_, Box<DocumentModel> b, __) {
        final docs = b.values.toList().reversed.take(5).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Recentes',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111111))),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen())),
                  child: const Text('Ver todos',
                      style: TextStyle(fontSize: 12, color: _kBlue)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...docs.map((doc) => _DocRow(doc: doc, fmt: _fmt)),
          ],
        );
      },
    );
  }
}

class _DocRow extends StatelessWidget {
  final DocumentModel doc;
  final String Function(DateTime) fmt;
  const _DocRow({required this.doc, required this.fmt});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PDFViewerScreen(path: doc.path))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder, width: 0.5),
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
                  const SizedBox(height: 2),
                  Text('PDF · ${fmt(doc.date)}',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFAAAAAA))),
                ],
              ),
            ),
            const Icon(Icons.more_vert, color: Color(0xFFCCCCCC), size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom Navigation ────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;
  final VoidCallback onScan;
  const _BottomNav(
      {required this.current, required this.onTap, required this.onScan});

  @override
  Widget build(BuildContext context) {
    // NavigationBar só reserva espaço para MediaQuery.padding.bottom (o
    // "safe area" visual), mas em ecrãs com navegação por gestos a zona de
    // deteção de gestos (systemGestureInsets.bottom) é maior do que isso —
    // sem esta compensação extra, a parte inferior dos botões fica dentro
    // dessa zona e os toques podem ser intercetados pelo gesto do sistema
    // em vez de chegarem à app.
    final gestureBottom = MediaQuery.systemGestureInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final extraBottom = math.max(0.0, gestureBottom - safeBottom);

    return Padding(
      padding: EdgeInsets.only(bottom: extraBottom),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: _kCard,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final active = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 10,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              color: active ? _kBlue : const Color(0xFFBBBBBB),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final active = states.contains(WidgetState.selected);
            return IconThemeData(
              color: active ? _kBlue : const Color(0xFFBBBBBB),
              size: 22,
            );
          }),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(height: 0.5, color: _kBorder),
            ),
            NavigationBar(
              selectedIndex: _toBarIndex(current),
              onDestinationSelected: (i) => onTap(_toLogicIndex(i)),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Início',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Docs',
                ),
                NavigationDestination(
                  icon: SizedBox(width: 48),
                  label: '',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: 'Recentes',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Perfil',
                ),
              ],
            ),
            Positioned(
              top: -16,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onScan,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _kBlue,
                      shape: BoxShape.circle,
                      border: Border.all(color: _kBg, width: 3),
                    ),
                    child: const Icon(Icons.document_scanner,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // lógico: 0=Início 1=Docs/Recentes(Histórico) 2=Perfil
  // O FAB (posição 2 da barra) tem o seu próprio callback (onScan) e não
  // faz parte deste espaço de índices — evita a colisão que fazia o botão
  // "Recentes" abrir o Scanner em vez de mudar de separador.
  int _toBarIndex(int logic) {
    if (logic == 0) return 0;
    if (logic == 1) return 1; // realça "Docs" — mesmo ecrã de "Recentes"
    if (logic == 2) return 4;
    return 0;
  }

  int _toLogicIndex(int bar) {
    if (bar == 0) return 0;
    if (bar == 1) return 1; // Docs → Histórico
    if (bar == 3) return 1; // Recentes → mesmo ecrã de Histórico
    if (bar == 4) return 2; // Perfil
    return 0;
  }
}
