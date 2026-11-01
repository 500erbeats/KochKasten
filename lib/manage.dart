import 'dart:math';
import 'package:flutter/material.dart';
import 'main.dart';
import 'paste_recipe.dart';

class ManagePage extends StatefulWidget {
  final List<Recipe> all;
  final VoidCallback onChanged;
  const ManagePage({super.key, required this.all, required this.onChanged});

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  String q = '';
  Cat? cat;
  final Set<String> sel = {};
  bool get selecting => sel.isNotEmpty;

  List<Recipe> get shown => widget.all
      .where((r) =>
          (cat == null || r.cat == cat) &&
          '${r.title} ${r.source}'.toLowerCase().contains(q.trim().toLowerCase()))
      .toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  Map<String, int> get _counts {
    final m = <String, int>{};
    for (final r in widget.all) {
      final k = r.title.trim().toLowerCase();
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  void _toggle(Recipe r) {
    setState(() {
      if (!sel.remove(r.id)) sel.add(r.id);
    });
  }

  Future<void> _edit(Recipe r) async {
    final res = await Navigator.push<Recipe>(
        context, MaterialPageRoute(builder: (_) => EditPage(recipe: r)));
    if (res == null) return;
    final i = widget.all.indexWhere((x) => x.id == res.id);
    if (i >= 0) widget.all[i] = res;
    widget.onChanged();
    setState(() {});
  }

  /// Änderung auf alle markierten Karten anwenden
  void _apply(void Function(Recipe) f) {
    for (final r in widget.all.where((r) => sel.contains(r.id))) {
      f(r);
    }
    widget.onChanged();
    setState(sel.clear);
  }

  Future<T?> _choose<T>(String title, List<(T, String)> options) => showDialog<T>(
        context: context,
        builder: (ctx) => SimpleDialog(title: Text(title), children: [
          for (final (v, label) in options)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, v), child: Text(label)),
        ]),
      );

  Future<void> _scan(Recipe r) async {
    final res = await Navigator.push<Recipe>(
        context, MaterialPageRoute(builder: (_) => PasteRecipePage(recipe: r)));
    if (res == null || !mounted) return;
    await _edit(res);
  }

  void _remove(List<Recipe> rs) {
    final removed = <(int, Recipe)>[];
    for (var i = 0; i < widget.all.length; i++) {
      if (rs.contains(widget.all[i])) removed.add((i, widget.all[i]));
    }
    if (removed.isEmpty) return;
    widget.all.removeWhere(rs.contains);
    widget.onChanged();
    setState(sel.clear);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(removed.length == 1
            ? '"${removed.first.$2.title}" gelöscht'
            : '${removed.length} Karten gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            for (final (i, r) in removed) {
              widget.all.insert(min(i, widget.all.length), r);
            }
            widget.onChanged();
            if (mounted) setState(() {});
          },
        ),
      ));
  }

  Future<void> _menu(String v) async {
    if (v == 'cat') {
      final c = await _choose<Cat>(
          'Kategorie ändern', [for (final k in Cat.values) (k, k.label)]);
      if (c != null) _apply((r) => r.cat = c);
    } else if (v == 'normal') {
      _apply((r) => r.special = false);
    } else if (v == 'special') {
      _apply((r) => r.special = true);
    } else if (v == 'effort') {
      final e = await _choose<Effort>(
          'Aufwand setzen', [for (final k in Effort.values) (k, k.label)]);
      if (e != null) _apply((r) => r.effort = e);
    } else if (v == 'fav') {
      _apply((r) => r.favorite = true);
    } else if (v == 'unfav') {
      _apply((r) => r.favorite = false);
    } else if (v == 'pause') {
      final d = await _choose<int>('Pausieren für …', const [
        (14, '2 Wochen'),
        (28, '4 Wochen'),
        (56, '8 Wochen'),
        (0, 'Pause aufheben'),
      ]);
      if (d != null) {
        _apply((r) => r.pausedUntil = d == 0 ? null : DateTime.now().add(Duration(days: d)));
      }
    } else if (v == 'delete') {
      _remove(widget.all.where((r) => sel.contains(r.id)).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = shown;
    final counts = _counts;
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(sel.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(
                    icon: const Icon(Icons.close), onPressed: () => setState(sel.clear)),
                title: Text('${sel.length} ausgewählt'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.select_all),
                    tooltip: 'Alle angezeigten',
                    onPressed: () => setState(() => sel.addAll(list.map((r) => r.id))),
                  ),
                  PopupMenuButton<String>(
                    onSelected: _menu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'cat', child: Text('Kategorie ändern …')),
                      PopupMenuItem(value: 'normal', child: Text('Als Normal markieren')),
                      PopupMenuItem(value: 'special', child: Text('Als Anlass markieren')),
                      PopupMenuItem(value: 'effort', child: Text('Aufwand setzen …')),
                      PopupMenuItem(value: 'fav', child: Text('Zu Favoriten hinzufügen')),
                      PopupMenuItem(value: 'unfav', child: Text('Aus Favoriten entfernen')),
                      PopupMenuItem(value: 'pause', child: Text('Pausieren …')),
                      PopupMenuItem(value: 'delete', child: Text('Löschen')),
                    ],
                  ),
                ],
              )
            : AppBar(title: Text('Alle Karten (${widget.all.length})')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Suchen (Name oder Kochbuch)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(
                  label: const Text('Alle'),
                  selected: cat == null,
                  onSelected: (_) => setState(() => cat = null)),
              for (final c in Cat.values)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                  label: Text(c.label),
                  selected: cat == c,
                  onSelected: (_) => setState(() => cat = c),
                ),
            ]),
          ),
          if (!selecting)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Tipp: Lange drücken zum Mehrfach-Auswählen',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          Expanded(
            child: ListView(children: [
              for (final r in list)
                ListTile(
                  selected: sel.contains(r.id),
                  leading: selecting
                      ? Checkbox(value: sel.contains(r.id), onChanged: (_) => _toggle(r))
                      : PopupMenuButton<Cat>(
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
                          child: CircleAvatar(radius: 14, backgroundColor: r.cat.color),
                        ),
                  title: Text(r.title),
                  subtitle: Text([
                    r.hasRecipe ? 'Rezept vorhanden' : 'Rezept fehlt',
                    if (r.special) '🎉 Anlass',
                    if (r.effort != Effort.medium) r.effort.label,
                    if (r.paused) '⏸ bis ${shortDate(r.pausedUntil!)}',
                    if (r.source.isNotEmpty) '📖 ${r.source}',
                    if ((counts[r.title.trim().toLowerCase()] ?? 0) > 1) 'doppelt!',
                  ].join(' · ')),
                  trailing: selecting
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!r.hasRecipe)
                        IconButton(
                          tooltip: 'Rezept einlesen',
                          icon: const Icon(Icons.document_scanner_outlined),
                          onPressed: () => _scan(r),
                        ),
                      IconButton(
                        icon: Icon(r.favorite ? Icons.star : Icons.star_border,
                            color: r.favorite ? Colors.amber.shade700 : null),
                        onPressed: () {
                          setState(() => r.favorite = !r.favorite);
                          widget.onChanged();
                        },
                      ),
                      IconButton(
                          icon: const Icon(Icons.delete_outline), onPressed: () => _remove([r])),
                    ]),
                  onTap: () => selecting ? _toggle(r) : _edit(r),
                  onLongPress: () => _toggle(r),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}