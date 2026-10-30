import 'dart:math';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'main.dart';

class CookModePage extends StatefulWidget {
  final Recipe recipe;
  const CookModePage({super.key, required this.recipe});

  @override
  State<CookModePage> createState() => _CookModePageState();
}

class _CookModePageState extends State<CookModePage> {
  double size = 20;
  late final List<String> steps = [
    for (final l in widget.recipe.instructions.split('\n'))
      if (l.trim().isNotEmpty) l.replaceFirst(RegExp(r'^\s*\d+[.)]\s*'), '').trim(),
  ];
  late final List<bool> ingDone = List.filled(widget.recipe.ingredients.length, false);
  late final List<bool> stepDone = List.filled(steps.length, false);

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // Display bleibt an
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  TextStyle _style(bool done) => TextStyle(
        fontSize: size,
        decoration: done ? TextDecoration.lineThrough : null,
        color: done ? Theme.of(context).disabledColor : null,
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    return Scaffold(
      appBar: AppBar(title: Text(r.title), actions: [
        IconButton(
            icon: const Icon(Icons.text_decrease),
            onPressed: () => setState(() => size = max(14, size - 2))),
        IconButton(
            icon: const Icon(Icons.text_increase),
            onPressed: () => setState(() => size = min(34, size + 2))),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (r.ingredients.isNotEmpty) ...[
          Text('Zutaten', style: Theme.of(context).textTheme.headlineSmall),
          for (var i = 0; i < r.ingredients.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: ingDone[i],
              onChanged: (v) => setState(() => ingDone[i] = v ?? false),
              title: Text(r.ingredients[i], style: _style(ingDone[i])),
            ),
          const SizedBox(height: 16),
        ],
        if (steps.isNotEmpty) ...[
          Text('Zubereitung', style: Theme.of(context).textTheme.headlineSmall),
          for (var i = 0; i < steps.length; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: stepDone[i],
              onChanged: (v) => setState(() => stepDone[i] = v ?? false),
              title: Text('${i + 1}. ${steps[i]}', style: _style(stepDone[i])),
            ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Fertig: heute gekocht'),
          onPressed: () => Navigator.pop(context, true),
        ),
      ]),
    );
  }
}