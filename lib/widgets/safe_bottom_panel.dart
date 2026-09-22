import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Envolve um painel fixo no fundo do ecrã garantindo que fica sempre acima
/// da zona de gestos do sistema. Em ecrãs com navegação por gestos (comum em
/// Samsung/One UI) essa zona (`systemGestureInsets.bottom`) é maior do que o
/// safe-area padrão (`padding.bottom`) — sem esta compensação extra, botões
/// perto do fundo ficam parcialmente cobertos pela barra do sistema e os
/// toques podem ser intercetados pelo gesto em vez de chegarem à app.
class SafeBottomPanel extends StatelessWidget {
  final Widget child;
  const SafeBottomPanel({super.key, required this.child});

  static double extraInset(BuildContext context) {
    final gestureBottom = MediaQuery.systemGestureInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return math.max(0.0, gestureBottom - safeBottom);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: extraInset(context)),
        child: child,
      ),
    );
  }
}
