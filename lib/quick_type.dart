import 'dart:math';
import 'package:flutter/material.dart';
import 'main.dart';

class QuickTypePage extends StatefulWidget {
  final List<Recipe> all;
  final VoidCallback onChanged;
  const QuickTypePage({super.key, required this.all, required this.onChanged});

  @override
  State<QuickTypePage> createState() => _QuickTypePageState();
}

class _QuickTypePageState extends State<QuickTypePage> {
  final ctrl = TextEditingController();
  final srcCtrl = TextEditingController();
  final focus = FocusNode();
  final added = <Recipe>[];
  Cat lastCat = Cat.fleisch;
  bool special = false; // bleibt für die nächsten Karten stehen

  @override
  void dispose() {
    ctrl.dispose();
    srcCtrl.dispose();
    focus.dispose();
    super.dispose();
  }

  void _add(Cat c) {
    final t = ctrl.text.trim();
    focus.requestFocus(); // Tastatur bleibt offen
    if (t.isEmpty) return;
    if (widget.all.any((r) => r.title.trim().toLowerCase() == t.toLowerCase())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"$t" gibt es schon')));
      return;
    }
    final r = Recipe(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: t,
      cat: c,
      source: srcCtrl.text.trim(),
      special: special,
    );
    widget.all.add(r);
    widget.onChanged();
    setState(() {
      added.insert(0, r);
      lastCat = c;
      ctrl.clear();
    });
  }

  void _removeWithUndo(Recipe r) {
    final idx = widget.all.indexOf(r);
    widget.all.remove(r);
    widget.onChanged();
    setState(() => added.remove(r));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('"${r.title}" gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            widget.all.insert(min(max(idx, 0), widget.all.length), r);
            widget.onChanged();
            if (mounted) setState(() => added.insert(0, r));
          },
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Karten eintippen (${added.length})')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onEditingComplete: () => _add(lastCat),
            decoration: InputDecoration(
              labelText: 'Name der Karte',
              border: const OutlineInputBorder(),
              helperText: 'Farbe antippen = speichern · Enter = ${lastCat.label}',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: srcCtrl,
            decoration: InputDecoration(
              labelText: 'Quelle / Kochbuch (optional)',
              isDense: true,
              border: const OutlineInputBorder(),
              helperText: 'Bleibt für die nächsten Karten stehen',
              suffixIcon:
                  IconButton(icon: const Icon(Icons.clear), onPressed: srcCtrl.clear),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false, label: Text('Normal'), icon: Icon(Icons.weekend_outlined)),
              ButtonSegment(
                  value: true, label: Text('Anlass'), icon: Icon(Icons.celebration)),
            ],
            selected: {special},
            onSelectionChanged: (s) {
              setState(() => special = s.first);
              focus.requestFocus();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: [
            for (final c in Cat.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 2),
                      side: lastCat == c
                          ? BorderSide(
                              color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                    ),
                    onPressed: () => _add(c),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(c.label, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView(children: [
            for (final r in added)
              ListTile(
                dense: true,
                leading: PopupMenuButton<Cat>(
                  tooltip: 'Kategorie ändern',
                  onSelected: (c) {
                    setState(() => r.cat = c);
                    widget.onChanged();
                  },
                  itemBuilder: (_) => [
                    for (final c in Cat.values)
                      PopupMenuItem(
                        value: c,
                        child: Row(children: [
                          CircleAvatar(radius: 8, backgroundColor: c.color),
                          const SizedBox(width: 8),
                          Text(c.label),
                        ]),
                      ),
                  ],
                  child: CircleAvatar(radius: 12, backgroundColor: r.cat.color),
                ),
                title: Text(r.title),
                subtitle: (r.source.isEmpty && !r.special)
                    ? null
                    : Text([
                        if (r.special) '🎉 Anlass',
                        if (r.source.isNotEmpty) '📖 ${r.source}',
                      ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeWithUndo(r),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}