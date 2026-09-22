import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

const _kGreen = Color(0xFF1E8E3E);
const _kRed = Color(0xFFD93025);
const _kBlue = Color(0xFF1A73E8);

double clampD(double v, double lo, double hi) => hi < lo ? lo : v.clamp(lo, hi);

/// Posição/tamanho/opções de uma assinatura sobreposta num documento —
/// partilhado entre o fluxo de digitalização (PreviewScreen) e a edição de
/// um documento já guardado (DocumentEditorScreen), para que o
/// comportamento de arrastar/redimensionar/data seja sempre o mesmo.
@immutable
class SignaturePlacement {
  /// Fração (0..1) da área da imagem onde fica o CENTRO da assinatura.
  final Offset anchor;

  /// Fator de escala (1.0 = tamanho base).
  final double scale;

  final bool includeDate;

  const SignaturePlacement({
    this.anchor = const Offset(0.8, 0.86),
    this.scale = 1.0,
    this.includeDate = false,
  });

  SignaturePlacement copyWith({
    Offset? anchor,
    double? scale,
    bool? includeDate,
  }) =>
      SignaturePlacement(
        anchor: anchor ?? this.anchor,
        scale: scale ?? this.scale,
        includeDate: includeDate ?? this.includeDate,
      );
}

/// Constrói os widgets Flutter (cartão arrastável + botões de remover e
/// redimensionar) para sobrepor a assinatura na pré-visualização — como uma
/// lista de widgets IRMÃOS a inserir no Stack do chamador, e não aninhados
/// dentro do detetor de arrasto do cartão, para o toque nos botões nunca
/// ser disputado com o gesto de mover.
List<Widget> buildDraggableSignatureWidgets({
  required Size box,
  required Uint8List signatureBytes,
  required SignaturePlacement placement,
  required String dateLabel,
  required ValueChanged<SignaturePlacement> onPlacementChanged,
  required VoidCallback onRemove,
  ValueChanged<bool>? onDraggingChanged,
}) {
  const baseW = 128.0;
  final baseH = placement.includeDate ? 60.0 : 44.0;
  final w = baseW * placement.scale;
  final h = baseH * placement.scale;
  const handle = 22.0;
  final left = clampD(placement.anchor.dx * box.width - w / 2, 0.0,
      math.max(0.0, box.width - w));
  final top = clampD(placement.anchor.dy * box.height - h / 2, 0.0,
      math.max(0.0, box.height - h));

  return [
    Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onPanStart: (_) => onDraggingChanged?.call(true),
        onPanUpdate: (details) {
          final newLeft = clampD(
              left + details.delta.dx, 0.0, math.max(0.0, box.width - w));
          final newTop = clampD(
              top + details.delta.dy, 0.0, math.max(0.0, box.height - h));
          onPlacementChanged(placement.copyWith(
            anchor: Offset(
              box.width == 0 ? 0.5 : (newLeft + w / 2) / box.width,
              box.height == 0 ? 0.5 : (newTop + h / 2) / box.height,
            ),
          ));
        },
        onPanEnd: (_) => onDraggingChanged?.call(false),
        onPanCancel: () => onDraggingChanged?.call(false),
        child: Container(
          width: w,
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kGreen, width: 1.2),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                  child: Image.memory(signatureBytes, fit: BoxFit.contain)),
              if (placement.includeDate)
                Text(dateLabel,
                    style:
                        const TextStyle(fontSize: 9, color: Color(0xFF444444))),
            ],
          ),
        ),
      ),
    ),

    // Remover — widget irmão independente do detetor de arrasto.
    Positioned(
      left: left + w - handle / 2,
      top: top - handle / 2,
      child: GestureDetector(
        onTap: onRemove,
        child: Container(
          width: handle,
          height: handle,
          decoration: const BoxDecoration(color: _kRed, shape: BoxShape.circle),
          child: const Icon(Icons.close, color: Colors.white, size: 14),
        ),
      ),
    ),

    // Redimensionar — idem, para o toque nunca ser disputado com o gesto
    // de mover o cartão.
    Positioned(
      left: left + w - handle / 2,
      top: top + h - handle / 2,
      child: GestureDetector(
        onPanUpdate: (details) {
          final delta = (details.delta.dx + details.delta.dy) / 2;
          onPlacementChanged(placement.copyWith(
            scale: (placement.scale + delta / 90).clamp(0.5, 3.0),
          ));
        },
        child: Container(
          width: handle,
          height: handle,
          decoration:
              const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
          child: const Icon(Icons.open_in_full, color: Colors.white, size: 12),
        ),
      ),
    ),
  ];
}

/// Posiciona a assinatura (e, opcionalmente, a data) no PDF final, no ponto
/// escolhido pelo utilizador — mesma lógica usada na pré-visualização.
List<pw.Widget> buildSignaturePdfWidgets(
  pw.MemoryImage sig, {
  required ({double x, double y, double w, double h}) rect,
  required SignaturePlacement placement,
  required String dateLabel,
}) {
  final sigW = 130.0 * placement.scale;
  final sigH = 46.0 * placement.scale;
  final cx = rect.x + placement.anchor.dx * rect.w;
  final cy = rect.y + placement.anchor.dy * rect.h;
  final left = clampD(cx - sigW / 2, rect.x, rect.x + rect.w - sigW);
  final top = clampD(cy - sigH / 2, rect.y, rect.y + rect.h - sigH);
  return [
    pw.Positioned(
      left: left,
      top: top,
      child: pw.SizedBox(
        width: sigW,
        child: pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.SizedBox(
              height: sigH,
              child: pw.Image(sig, fit: pw.BoxFit.contain),
            ),
            if (placement.includeDate)
              pw.Text(dateLabel,
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey700)),
          ],
        ),
      ),
    ),
  ];
}
