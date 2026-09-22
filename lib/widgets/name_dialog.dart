import 'package:flutter/material.dart';

/// Diálogo para pedir/editar um nome — dono do seu próprio
/// `TextEditingController`, destruído no `dispose()` do próprio State.
///
/// Isto importa: se o controller for destruído pelo chamador logo que o
/// diálogo devolve um valor (ex.: `showDialog(...).then((_) => ctrl.dispose())`),
/// o TextField ainda pode estar montado — a animação de saída do diálogo só
/// termina depois — e usar um controller já destruído nessa janela
/// ("A TextEditingController was used after being disposed") corrompe a
/// árvore de widgets e pode crashar a app. Ao viver dentro do próprio
/// StatefulWidget, o Flutter só chama dispose() quando o widget é
/// realmente removido da árvore.
class NameDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String confirmLabel;

  const NameDialog({
    super.key,
    required this.title,
    required this.initialValue,
    this.confirmLabel = 'Guardar',
  });

  @override
  State<NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<NameDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _ctrl.text.trim();
    Navigator.pop(context, name.isEmpty ? widget.initialValue : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Nome do documento'),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
