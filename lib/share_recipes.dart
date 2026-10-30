import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'main.dart';

class ImportResult {
  final List<Recipe> fresh; // neue Karten
  final int filled; // leere Karten, die ein Rezept bekommen haben
  ImportResult(this.fresh, this.filled);
}

/// Exportiert Rezepte als JSON und öffnet das Teilen-Menü.
/// full = Backup mit persönlichen Daten (zuletzt gekocht, Favorit, Pause).
/// Gibt false zurück, wenn das Teilen abgebrochen wurde.
Future<bool> exportRecipes(List<Recipe> list, {bool full = false}) async {
  final data = {
    'format': 'rezeptkarten',
    'version': 1,
    'full': full,
    'recipes': [
      for (final r in list)
        {
          'title': r.title,
          'cat': r.cat.name,
          'ingredients': r.ingredients,
          'instructions': r.instructions,
          'source': r.source,
          'special': r.special,
          'effort': r.effort.name,
          if (full) ...{
            'favorite': r.favorite,
            'lastCooked': r.lastCooked?.toIso8601String(),
            'pausedUntil': r.pausedUntil?.toIso8601String(),
          },
        }
    ],
  };
  final d = DateTime.now();
  final stamp =
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final dir = await Directory.systemTemp.createTemp('export');
  final f = File('${dir.path}/${full ? 'kochkasten-backup-$stamp' : 'rezepte'}.json');
  await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  final res = await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path)], subject: full ? 'KochKasten Backup' : 'Rezepte'));
  return res.status != ShareResultStatus.dismissed;
}

DateTime? _date(dynamic s) => s is String ? DateTime.tryParse(s) : null;

Recipe _fromMap(dynamic x, String id) => Recipe(
      id: id,
      title: '${x['title']}'.trim(),
      cat: Cat.values.asNameMap()[x['cat']] ?? Cat.fleisch,
      ingredients: List<String>.from(x['ingredients'] ?? []),
      instructions: '${x['instructions'] ?? ''}',
      source: '${x['source'] ?? ''}',
      special: x['special'] == true,
      effort: Effort.values.asNameMap()[x['effort']] ?? Effort.medium,
      favorite: x['favorite'] == true,
      lastCooked: _date(x['lastCooked']),
      pausedUntil: _date(x['pausedUntil']),
    );

/// Datei wählen, prüfen, Rückfrage.
/// Neue Karten werden zurückgegeben, leere vorhandene Karten werden direkt mit dem Rezept gefüllt.
Future<ImportResult?> importRecipes(BuildContext context, List<Recipe> existing) async {
  final files = await FilePicker.pickFiles(
      type: FileType.custom, allowedExtensions: ['json']);
  final path = files.isEmpty ? null : files.first.path;
  if (path == null) return null;
  final bytes = await File(path).readAsBytes();

  List raw;
  try {
    final j = jsonDecode(utf8.decode(bytes));
    if (j['format'] != 'rezeptkarten') throw 'falsches Format';
    raw = j['recipes'] as List;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Datei nicht lesbar')));
    }
    return null;
  }

  final byTitle = {for (final r in existing) r.title.trim().toLowerCase(): r};
  final seenNew = <String>{};
  final fresh = <Recipe>[];
  final fills = <(Recipe, dynamic)>[];
  var skipped = 0;
  for (final x in raw) {
    final t = '${x['title']}'.trim();
    if (t.isEmpty) continue;
    final key = t.toLowerCase();
    final ex = byTitle[key];
    if (ex != null) {
      final hasRec = (x['ingredients'] is List && (x['ingredients'] as List).isNotEmpty) ||
          '${x['instructions'] ?? ''}'.trim().isNotEmpty;
      if (!ex.hasRecipe && hasRec) {
        fills.add((ex, x));
      } else {
        skipped++;
      }
      continue;
    }
    if (!seenNew.add(key)) {
      skipped++;
      continue;
    }
    fresh.add(_fromMap(x, '${DateTime.now().microsecondsSinceEpoch}${fresh.length}'));
  }

  if (!context.mounted) return null;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Importieren'),
      content: Text('${raw.length} Karten in der Datei:\n'
          '• ${fresh.length} neu\n'
          '• ${fills.length} leere Karten bekommen ihr Rezept\n'
          '• $skipped übersprungen (schon vorhanden)'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(
            onPressed: (fresh.isEmpty && fills.isEmpty) ? null : () => Navigator.pop(ctx, true),
            child: const Text('Importieren')),
      ],
    ),
  );
  if (ok != true) return null;

  for (final (ex, x) in fills) {
    ex.ingredients = List<String>.from(x['ingredients'] ?? []);
    ex.instructions = '${x['instructions'] ?? ''}';
    if (ex.source.isEmpty) ex.source = '${x['source'] ?? ''}';
  }
  return ImportResult(fresh, fills.length);
}