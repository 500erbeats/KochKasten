import 'package:flutter/material.dart';
import 'main.dart';

enum PageMode {
  ingredients('Zutaten'),
  steps('Zubereitung'),
  mixed('Gemischt');

  final String label;
  const PageMode(this.label);
}

bool looksLikeIngredient(String s) {
  if (RegExp(r'^\d+[.)]\s').hasMatch(s)) return false; // "1. Zwiebel schälen" = Schritt
  if (s.length > 50 || RegExp(r'[.!?]$').hasMatch(s)) return false;
  return RegExp(
          r'^(\d|½|¼|¾|etwas\b|eine?\b|einen\b|ein paar\b|prise\b|msp\b|bund\b|schuss\b|nach geschmack)',
          caseSensitive: false)
      .hasMatch(s);
}

/// Zeilen zu Schritten zusammensetzen: neue Nummer oder Satzende = neuer Schritt
List<String> stepsFromRows(List<String> rows) {
  final out = <String>[];
  var cur = '';
  void flush() {
    if (cur.trim().isNotEmpty) out.add(cur.trim());
    cur = '';
  }

  final num = RegExp(r'^\d+[.)]\s*');
  for (final r in rows) {
    if (num.hasMatch(r)) {
      flush();
      cur = r.replaceFirst(num, '');
    } else if (cur.endsWith('-')) {
      cur = cur.substring(0, cur.length - 1) + r;
    } else {
      cur = cur.isEmpty ? r : '$cur $r';
    }
    if (RegExp(r'[.!?]$').hasMatch(cur)) flush();
  }
  flush();
  return out;
}

({List<String> ing, List<String> steps}) parseRecipeText(String text, PageMode mode) {
  final rows =
      text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final ing = <String>[];
  final steps = <String>[];
  if (mode == PageMode.ingredients) {
    ing.addAll(rows);
  } else if (mode == PageMode.steps) {
    steps.addAll(stepsFromRows(rows));
  } else {
    final head = RegExp(r'^(zutaten|zubereitung|rezept|anleitung)\b[:\s]*(.*)$',
        caseSensitive: false);
    bool? inIng;
    final stepRows = <String>[];
    for (final r in rows) {
      var line = r;
      final m = head.firstMatch(r);
      if (m != null) {
        inIng = m.group(1)!.toLowerCase() == 'zutaten';
        line = m.group(2)!.trim();
        if (line.isEmpty) continue;
      }
      if (inIng ?? looksLikeIngredient(line)) {
        ing.add(line);
      } else {
        stepRows.add(line);
      }
    }
    steps.addAll(stepsFromRows(stepRows));
  }
  return (ing: ing, steps: steps);
}

class PasteRecipePage extends StatefulWidget {
  final Recipe recipe;
  const PasteRecipePage({super.key, required this.recipe});

  @override
  State<PasteRecipePage> createState() => _PasteRecipePageState();
}

class _PasteRecipePageState extends State<PasteRecipePage> {
  final ctrl = TextEditingController();
  PageMode mode = PageMode.mixed;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _go() {
  final r = widget.recipe;
  final p = parseRecipeText(ctrl.text, mode);
  final old = [
    for (final l in r.instructions.split('\n'))
      if (l.trim().isNotEmpty) l.replaceFirst(RegExp(r'^\s*\d+\.\s*'), '').trim(),
  ];
  final steps = [...old, ...p.steps];
  Navigator.pop(
    context,
    r.copyWith(
      ingredients: [...r.ingredients, ...p.ing],
      instructions:
          steps.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n'),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.recipe.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text(
              'Text aus dem Kochbuch hier einfügen oder eintippen. Auf dem iPhone: '
              'Foto in der Fotos-App öffnen, unten rechts das Live-Text-Symbol antippen, '
              'Text markieren und kopieren.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          SegmentedButton<PageMode>(
            segments: [
              for (final m in PageMode.values) ButtonSegment(value: m, label: Text(m.label))
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                  border: OutlineInputBorder(), hintText: 'Hier einfügen …'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _go, child: const Text('Weiter zum Prüfen')),
          ),
        ]),
      ),
    );
  }
}