import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/document_model.dart';
import '../services/import_service.dart';
import 'scanner_screen.dart';
import 'history_screen.dart';
import 'pdf_tools_screen.dart';
import 'quick_ocr_screen.dart';
import 'signature_library_screen.dart';
import 'tools_screen.dart';
import 'profile_screen.dart';
import '../widgets/document_tile.dart'
    show showDocumentOptions, renameDocument, openDocument;
import '../widgets/document_thumbnail.dart';
import '../widgets/safe_bottom_panel.dart';

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
  // 0 = Início · 1 = Todos os Documentos · 2 = Ferramentas · 3 = Eu
  int _tab = 0;

  void _onNav(int i) => setState(() => _tab = i);

  void _openScanner() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
  }

  static const _tabs = [
    _HomeTab(),
    HistoryScreen(),
    ToolsScreen(),
    ProfileScreen(),
  ];

  Future<void> _confirmExit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair da aplicação'),
        content: const Text('Deseja sair do MS ScanNow?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmed == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // No separador Início, o back pede confirmação antes de sair da
        // app; nos outros separadores, volta primeiro ao Início — só quem
        // já está no Início é que vê o diálogo de saída.
        if (_tab != 0) {
          setState(() => _tab = 0);
        } else {
          _confirmExit();
        }
      },
      child: Scaffold(
        backgroundColor: _kBg,
        body: IndexedStack(
          index: _tab.clamp(0, _tabs.length - 1),
          children: _tabs,
        ),
        bottomNavigationBar:
            _BottomNav(current: _tab, onTap: _onNav, onScan: _openScanner),
      ),
    );
  }
}

// ─── Tab Início ───────────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  const _HomeTab();
  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          _Header(controller: _searchCtrl, onChanged: _onSearchChanged, onClear: _clearSearch),
          Expanded(
            child: _query.isEmpty
                ? const SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(14, 16, 14, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuickGrid(),
                        SizedBox(height: 20),
                        _RecentDocs(),
                      ],
                    ),
                  )
                : _SearchResults(query: _query),
          ),
        ],
      ),
    );
  }
}

// ─── Header com pesquisa inline ──────────────────────────────────────────────

class _Header extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _Header({required this.controller, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      color: _kBlue,
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logotipo real num cartão branco — garante contraste
                    // independentemente das cores do logo, em vez de o pôr
                    // diretamente sobre o azul do cabeçalho.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.asset('assets/images/logo.png',
                          height: 20, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 6),
                    const Text('Scan · PDF · OCR · Assinatura',
                        style: TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ),
              ),
              const CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white24,
                child:
                    Icon(Icons.person_outline, color: Colors.white, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Pesquisa incremental (debounce) sobre a lista local de
          // documentos — em vez de abrir um SearchDelegate à parte.
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.search, color: Colors.white60, size: 17),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Pesquisar documentos...',
                      hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: controller,
                  builder: (_, TextEditingValue v, __) => v.text.isEmpty
                      ? const SizedBox(width: 12)
                      : IconButton(
                          icon: const Icon(Icons.clear,
                              color: Colors.white60, size: 17),
                          onPressed: onClear,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Resultados de pesquisa ───────────────────────────────────────────────────

class _SearchResults extends StatelessWidget {
  final String query;
  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<DocumentModel>('documents');
    return ValueListenableBuilder(
      valueListenable: box.listenable(),
      builder: (_, Box<DocumentModel> b, __) {
        final results = b.values
            .where((d) => d.name.toLowerCase().contains(query.toLowerCase()))
            .toList()
            .reversed
            .toList();

        if (results.isEmpty) {
          return Center(
            child: Text('Nenhum resultado para "$query"',
                style: const TextStyle(fontSize: 14, color: Color(0xFF999999))),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: results.length,
          itemBuilder: (_, i) => _DocRow(doc: results[i]),
        );
      },
    );
  }
}

// ─── Grelha de acessos rápidos (2 linhas x 4 colunas) ────────────────────────

class _QuickGrid extends StatelessWidget {
  const _QuickGrid();

  static const _items = [
    _QItem('Smart Scan', Icons.document_scanner_outlined, _kBlue),
    _QItem('Cartões ID', Icons.credit_card_outlined, Color(0xFFF9AB00)),
    _QItem('Ferramentas PDF', Icons.merge_type, Color(0xFF8E44AD)),
    _QItem('Extrair Texto', Icons.text_fields, Color(0xFF00ACC1)),
    _QItem('Importar Imagens', Icons.photo_library_outlined, Color(0xFF1E8E3E)),
    _QItem('Importar Ficheiros', Icons.upload_file_outlined, Color(0xFFD93025)),
    _QItem('Assinar', Icons.draw_outlined, Color(0xFF3949AB)),
    _QItem('Ver Tudo', Icons.grid_view_outlined, Color(0xFF757575)),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 4,
      mainAxisSpacing: 12,
      childAspectRatio: 0.72,
      children: _items
          .map((item) => _QuickCard(item: item, onTap: () => _onTap(context, item.label)))
          .toList(),
    );
  }

  void _onTap(BuildContext context, String label) {
    switch (label) {
      case 'Smart Scan':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
        break;
      case 'Cartões ID':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ScannerScreen(initialMode: ScanMode.id)));
        break;
      case 'Ferramentas PDF':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PdfToolsScreen()));
        break;
      case 'Extrair Texto':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const QuickOcrScreen()));
        break;
      case 'Importar Imagens':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ScannerScreen(startWithGallery: true)));
        break;
      case 'Importar Ficheiros':
        _importFile(context);
        break;
      case 'Assinar':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SignatureLibraryScreen()));
        break;
      case 'Ver Tudo':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
        break;
    }
  }

  Future<void> _importFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final doc = await ImportService.importPdf();
      if (doc == null) return;
      messenger.showSnackBar(SnackBar(
          content: Text('"${doc.name}" importado.'),
          behavior: SnackBarBehavior.floating));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Não foi possível importar o ficheiro.')));
    }
  }
}

class _QItem {
  final String label;
  final IconData icon;
  final Color color;
  const _QItem(this.label, this.icon, this.color);
}

class _QuickCard extends StatelessWidget {
  final _QItem item;
  final VoidCallback onTap;
  const _QuickCard({required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [item.color, Color.lerp(item.color, Colors.black, 0.22)!],
              ),
              boxShadow: [
                BoxShadow(
                    color: item.color.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3)),
              ],
            ),
            child: Icon(item.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF222222))),
        ],
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
  final String Function(DateTime)? fmt;
  const _DocRow({required this.doc, this.fmt});

  static const _months = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
    'jul', 'ago', 'set', 'out', 'nov', 'dez'
  ];

  String _defaultFmt(DateTime dt) => '${dt.day} ${_months[dt.month - 1]} ${dt.year}';

  @override
  Widget build(BuildContext context) {
    final format = fmt ?? _defaultFmt;
    return GestureDetector(
      onTap: () => openDocument(context, doc),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder, width: 0.5),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            DocumentThumbnail(
              document: doc,
              width: 34,
              height: 42,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => renameDocument(context, doc),
                    child: Text(doc.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF111111))),
                  ),
                  const SizedBox(height: 2),
                  Text(
                      'PDF · ${format(doc.date)}'
                      '${doc.pageCount > 1 ? ' · ${doc.pageCount} pág.' : ''}',
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFFAAAAAA))),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => showDocumentOptions(context, doc),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child:
                    Icon(Icons.more_vert, color: Color(0xFFCCCCCC), size: 16),
              ),
            ),
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

  // Largura fixa reservada para o botão de scan flutuante — em vez de uma
  // posição extra da barra vazia com a mesma largura dos itens reais (o que
  // deixava um espaço morto enorme ao centro), este vão tem só a largura
  // que o botão precisa.
  static const _fabGap = 64.0;

  @override
  Widget build(BuildContext context) {
    return SafeBottomPanel(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 64,
            decoration: const BoxDecoration(
              color: _kCard,
              border: Border(top: BorderSide(color: _kBorder, width: 0.5)),
            ),
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Início',
                  active: current == 0,
                  onTap: () => onTap(0),
                ),
                _NavItem(
                  icon: Icons.folder_outlined,
                  selectedIcon: Icons.folder,
                  label: 'Documentos',
                  active: current == 1,
                  onTap: () => onTap(1),
                ),
                const SizedBox(width: _fabGap),
                _NavItem(
                  icon: Icons.build_outlined,
                  selectedIcon: Icons.build,
                  label: 'Ferramentas',
                  active: current == 2,
                  onTap: () => onTap(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: 'Eu',
                  active: current == 3,
                  onTap: () => onTap(3),
                ),
              ],
            ),
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
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? _kBlue : const Color(0xFFBBBBBB);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? selectedIcon : icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: color,
                )),
          ],
        ),
      ),
    );
  }
}
