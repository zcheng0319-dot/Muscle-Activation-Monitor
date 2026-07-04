import 'package:flutter/material.dart';

class CatalogNameDialog extends StatefulWidget {
  const CatalogNameDialog({
    required this.title,
    required this.label,
    this.initialValue = '',
    super.key,
  });

  final String title;
  final String label;
  final String initialValue;

  @override
  State<CatalogNameDialog> createState() => _CatalogNameDialogState();
}

class _CatalogNameDialogState extends State<CatalogNameDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('catalog-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 50,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.label,
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty || name.length > 50) {
      setState(() {
        _errorText = 'Enter 1 to 50 characters.';
      });
      return;
    }
    Navigator.of(context).pop(name);
  }
}
