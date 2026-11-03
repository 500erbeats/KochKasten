import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

/// Zutaten eines Gerichts auswählen und an Apple Erinnerungen (über einen Kurzbefehl) senden
Future<void> showIngredientExport(BuildContext context, Recipe r) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExportSheet(recipe: r, prefs: prefs),
  );
}

class _ExportSheet extends StatefulWidget {
  final Recipe recipe;
  final SharedPreferences prefs;
  const _ExportSheet({required this.recipe, required this.prefs});

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  late final List<bool> pick = List.filled(widget.recipe.ingredients.length, true);
  late final TextEditingController name = TextEditingController(
      text: widget.prefs.getString('shortcutName') ?? 'KochKasten Einkauf');

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  List<String> get chosen => [
        for (var i = 0; i < pick.length; i++)
          if (pick[i]) widget.recipe.ingredients[i]
      ];

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  Future<void> _send() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      _msg('Bitte den Namen deines Kurzbefehls eintragen');
      return;
    }
    await widget.prefs.setString('shortcutName', n);
    final uri = Uri.parse('shortcuts://run-shortcut'
        '?name=${Uri.encodeComponent(n)}'
        '&input=text'
        '&text=${Uri.encodeComponent(chosen.join('\n'))}');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
      } else {
        _msg('Die Kurzbefehle-App ließ sich nicht öffnen');
      }
    } catch (_) {
      _msg('Die Kurzbefehle-App ließ sich nicht öffnen');
    }
  }

  Future<void> _share() async {
    await SharePlus.instance
        .share(ShareParams(text: chosen.join('\n'), subject: widget.recipe.title));
  }

  void _help() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Einmalig einen Kurzbefehl anlegen'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Kurzbefehle-App öffnen, oben auf + tippen.\n'
            '2. Name genau so wie im Feld eintragen (z. B. KochKasten Einkauf).\n'
            '3. Aktion "Text aufteilen": Text = Kurzbefehl-Eingabe, Trennzeichen = Neue Zeilen.\n'
            '4. Aktion "Mit jedem Element wiederholen" (englisch: Repeat with Each) auf das Ergebnis.\n'
            '5. Darin "Neue Erinnerung hinzufügen": Titel = Wiederholungselement, '
            'Liste = deine Einkaufsliste.\n'
            '6. Beim ersten Start fragt iOS nach dem Zugriff auf Erinnerungen.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recipe;
    final n = chosen.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text('Einkauf: ${r.title}',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Kurzbefehl einrichten',
              onPressed: _help),
        ]),
        Row(children: [
          TextButton(
              onPressed: () => setState(() => pick.fillRange(0, pick.length, true)),
              child: const Text('Alle')),
          TextButton(
              onPressed: () => setState(() => pick.fillRange(0, pick.length, false)),
              child: const Text('Keine')),
        ]),
        Flexible(
          child: ListView(shrinkWrap: true, children: [
            for (var i = 0; i < r.ingredients.length; i++)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: pick[i],
                onChanged: (v) => setState(() => pick[i] = v ?? false),
                title: Text(r.ingredients[i]),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Name deines Kurzbefehls',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: n == 0 ? null : _send,
              icon: const Icon(Icons.checklist),
              label: Text('An Erinnerungen ($n)'),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: n == 0 ? null : _share,
            icon: const Icon(Icons.ios_share),
            label: const Text('Text'),
          ),
        ]),
      ]),
    );
  }
}