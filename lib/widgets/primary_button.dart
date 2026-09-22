import 'package:flutter/material.dart';

/// Botão de ação principal com gradiente e sombra colorida — usado nas
/// acções-chave (guardar PDF, confirmar assinatura...) em vez do
/// FilledButton plano por omissão do Material, que lê como um botão
/// genérico de qualquer template.
class PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String label;
  final Color color;
  final double height;

  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    final end = Color.lerp(color, Colors.black, 0.22)!;
    final fg = disabled ? Colors.grey.shade500 : Colors.white;

    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: disabled
                ? null
                : LinearGradient(
                    colors: [color, end],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: disabled ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(color: fg, size: 20),
                  child: icon,
                ),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
