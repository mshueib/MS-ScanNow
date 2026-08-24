import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

const _kBlue = Color(0xFF1A73E8);

class SignatureScreen extends StatefulWidget {
  final void Function(Uint8List bytes)? onSigned;
  const SignatureScreen({super.key, this.onSigned});
  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  Color _penColor = Colors.black;
  double _penWidth = 2.5;
  bool _hasDrawn = false;

  // O controller é recriado sempre que se muda cor ou espessura,
  // pois o pacote `signature` não expõe setters para essas propriedades.
  SignatureController _ctrl = SignatureController(
    penStrokeWidth: 2.5,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onDraw);
  }

  void _onDraw() {
    if (mounted) setState(() => _hasDrawn = _ctrl.isNotEmpty);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onDraw);
    _ctrl.dispose();
    super.dispose();
  }

  // ─── Acções ───────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    if (!_ctrl.isNotEmpty) return;
    final bytes = await _ctrl.toPngBytes();
    if (bytes == null || !mounted) return;
    widget.onSigned?.call(bytes);
    Navigator.pop(context, bytes);
  }

  void _clear() {
    _ctrl.clear();
    setState(() => _hasDrawn = false);
  }

  /// Recria o controller com nova cor — única forma suportada pelo pacote.
  void _setPenColor(Color c) {
    _rebuildController(color: c, width: _penWidth);
    setState(() => _penColor = c);
  }

  /// Recria o controller com nova espessura.
  void _setPenWidth(double w) {
    _rebuildController(color: _penColor, width: w);
    setState(() => _penWidth = w);
  }

  void _rebuildController({required Color color, required double width}) {
    final old = _ctrl;
    old.removeListener(_onDraw);
    final next = SignatureController(
      penStrokeWidth: width,
      penColor: color,
      exportBackgroundColor: Colors.white,
    );
    next.addListener(_onDraw);
    setState(() {
      _ctrl = next;
      _hasDrawn = false;
    });
    // Dispose após o setState para não quebrar o widget que ainda usa old
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  // ─── Opções de cor e espessura ────────────────────────────────────────────

  static const _colors = <Color>[
    Colors.black,
    Color(0xFF1A73E8),
    Color(0xFF1E8E3E),
    Color(0xFFD93025),
  ];

  static const _widths = <double>[1.5, 2.5, 4.0];

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Assinatura Digital'),
        centerTitle: true,
        backgroundColor: _kBlue,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _clear,
            child:
                const Text('Limpar', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Assine com o dedo ou com a caneta',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF636366)),
            ),
            const SizedBox(height: 12),

            // Área de assinatura
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: _kBlue.withValues(alpha: 0.25), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(children: [
                    Signature(
                      controller: _ctrl,
                      backgroundColor: Colors.white,
                    ),
                    // Linha de base
                    Positioned(
                      bottom: 50,
                      left: 40,
                      right: 40,
                      child: Container(height: 1, color: Colors.grey.shade200),
                    ),
                    Positioned(
                      bottom: 36,
                      left: 40,
                      child: Text('Assinatura',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey.shade400)),
                    ),
                    if (!_hasDrawn)
                      Center(
                        child: Text('Assine aqui',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey.shade300)),
                      ),
                  ]),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Controlos: cor e espessura
            Row(
              children: [
                const Text('Cor:',
                    style: TextStyle(fontSize: 12, color: Color(0xFF636366))),
                const SizedBox(width: 8),
                ..._colors.map((c) => GestureDetector(
                      onTap: () => _setPenColor(c),
                      child: Container(
                        width: 28,
                        height: 28,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _penColor == c
                                ? Colors.white
                                : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: _penColor == c
                              ? [
                                  BoxShadow(
                                      color: c.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                      spreadRadius: 1)
                                ]
                              : null,
                        ),
                      ),
                    )),
                const Spacer(),
                const Text('Esp.:',
                    style: TextStyle(fontSize: 12, color: Color(0xFF636366))),
                const SizedBox(width: 6),
                ..._widths.map((w) => GestureDetector(
                      onTap: () => _setPenWidth(w),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: _penWidth == w
                              ? _kBlue.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                _penWidth == w ? _kBlue : Colors.grey.shade300,
                            width: 0.5,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: w * 4,
                            height: w,
                            decoration: BoxDecoration(
                              color: _penColor,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                    )),
              ],
            ),

            const SizedBox(height: 16),

            // Botões
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _hasDrawn ? _confirm : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _kBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.check),
                    label: const Text('Confirmar assinatura'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
