import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'main.dart';
import 'ocr.dart';

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
      // Stehen die Überschriften im Text, entscheidet der Text und nicht die Auswahl oben
  final hasHeadings = rows.any((r) =>
      RegExp(r'^(zutaten|zubereitung|anleitung)\s*:?$', caseSensitive: false).hasMatch(r));
  if (hasHeadings) mode = PageMode.mixed;
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
bool smart = true; // Layout erkennen (Spalten, Zutaten/Zubereitung)
  bool busy = false;

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _photo(ImageSource src) async {
  final f = await pickPhoto(src);
  if (f == null) return;
  setState(() => busy = true);
  try {
    final t = smart ? await ocrRecipe(f) : await ocrText(f);
    if (!mounted) return;
    if (t.trim().isEmpty) {
      _msg('Kein Text erkannt. Näher ran, gerade fotografieren, besseres Licht?');
    } else {
      setState(() {
        final cur = ctrl.text.trimRight();
        ctrl.text = cur.isEmpty ? t : '$cur\n$t';
        if (smart) mode = PageMode.mixed;
      });
    }
  } catch (e) {
    _msg('$e');
  }
  if (mounted) setState(() => busy = false);
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
              'Foto einer gedruckten Kochbuchseite machen oder Text einfügen bzw. tippen. '
              'Den erkannten Text unten prüfen und korrigieren.',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : () => _photo(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Foto'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _photo(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galerie'),
              ),
            ),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: const Text('Layout erkennen (Spalten, Zutaten/Zubereitung)'),
              selected: smart,
              onSelected: (v) => setState(() => smart = v),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Der Text enthält:', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(height: 4),
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
                  border: OutlineInputBorder(), hintText: 'Erkannter oder eingefügter Text …'),
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