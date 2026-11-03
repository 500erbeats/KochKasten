import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'colors.dart';
import 'cook_mode.dart';
import 'manage.dart';
import 'paste_recipe.dart';
import 'quick_type.dart';
import 'share_recipes.dart';
import 'slot.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'export_reminders.dart';

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final p = await SharedPreferences.getInstance();
  themeNotifier.value =
      ThemeMode.values.asNameMap()[p.getString('theme')] ?? ThemeMode.system;
  runApp(const KochKastenApp());
}

class KochKastenApp extends StatelessWidget {
  const KochKastenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: 'KochKasten',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        locale: const Locale('de'),
        supportedLocales: const [Locale('de')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepOrange),
        darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.deepOrange,
            brightness: Brightness.dark),
        home: const HomePage(),
      ),
    );
  }
}

enum Cat {
  fleisch('Fleisch', [229, 57, 53]),
  fisch('Fisch', [30, 136, 229]),
  veggie('Vegetarisch', [67, 160, 71]),
  suess('Süß', [216, 27, 96]),
  party('Party', [251, 140, 0]);

  final String label;
  final List<int> defRgb;
  const Cat(this.label, this.defRgb);

  /// Selbst gewählte Farbe, sonst Standardfarbe
  Color get color {
    final v = catRgb[this] ?? defRgb;
    return Color.fromARGB(255, v[0], v[1], v[2]);
  }
}

final Map<Cat, List<int>> catRgb = {};

enum Effort {
  quick('Schnell', Icons.bolt),
  medium('Mittel', Icons.timelapse),
  elaborate('Aufwendig', Icons.hourglass_bottom);

  final String label;
  final IconData icon;
  const Effort(this.label, this.icon);
}

class Recipe {
  String id, title, instructions, source;
  Cat cat;
  Effort effort;
  bool special; // false = Normal, true = Anlass
  bool favorite;
  List<String> ingredients;
  DateTime? lastCooked;
  DateTime? pausedUntil;

  Recipe({
    required this.id,
    required this.title,
    required this.cat,
    this.ingredients = const [],
    this.instructions = '',
    this.source = '',
    this.special = false,
    this.favorite = false,
    this.effort = Effort.medium,
    this.lastCooked,
    this.pausedUntil,
  });

  bool get hasRecipe => ingredients.isNotEmpty || instructions.trim().isNotEmpty;
  bool get paused => pausedUntil != null && pausedUntil!.isAfter(DateTime.now());

  Recipe copyWith({List<String>? ingredients, String? instructions}) => Recipe(
        id: id,
        title: title,
        cat: cat,
        ingredients: ingredients ?? this.ingredients,
        instructions: instructions ?? this.instructions,
        source: source,
        special: special,
        favorite: favorite,
        effort: effort,
        lastCooked: lastCooked,
        pausedUntil: pausedUntil,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'cat': cat.name,
        'ing': ingredients,
        'ins': instructions,
        'src': source,
        'occ': special,
        'fav': favorite,
        'eff': effort.name,
        'last': lastCooked?.toIso8601String(),
        'pause': pausedUntil?.toIso8601String(),
      };

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
        id: j['id'],
        title: j['title'],
        cat: Cat.values.byName(j['cat']),
        ingredients: List<String>.from(j['ing']),
        instructions: j['ins'],
        source: j['src'] ?? '',
        special: j['occ'] ?? false,
        favorite: j['fav'] ?? false,
        effort: Effort.values.asNameMap()[j['eff']] ?? Effort.medium,
        lastCooked: j['last'] == null ? null : DateTime.parse(j['last']),
        pausedUntil: j['pause'] == null ? null : DateTime.parse(j['pause']),
      );
}

String ago(DateTime? d) {
  if (d == null) return 'noch nie gekocht';
  final n = DateTime.now().difference(d).inDays;
  if (n == 0) return 'heute gekocht';
  if (n == 1) return 'gestern gekocht';
  if (n < 14) return 'zuletzt vor $n Tagen';
  if (n < 60) return 'zuletzt vor ${n ~/ 7} Wochen';
  return 'zuletzt vor ${n ~/ 30} Monaten';
}

String shortDate(DateTime d) => '${d.day}.${d.month}.';

class RecipeTile extends StatelessWidget {
  final Recipe r;
  final String? extra;
  final VoidCallback onTap;
  final VoidCallback? onCooked; // Tippen: heute gekocht
  final VoidCallback? onCookedPick; // Lang drücken: Datum wählen
  const RecipeTile({
    super.key,
    required this.r,
    required this.onTap,
    this.extra,
    this.onCooked,
    this.onCookedPick,
  });

  @override
  Widget build(BuildContext context) {
    final sub = [
      if (extra != null) extra!,
      ago(r.lastCooked),
      if (r.paused) '⏸ bis ${shortDate(r.pausedUntil!)}',
      if (r.special) '🎉 Anlass',
      if (r.effort != Effort.medium)
        r.effort == Effort.quick ? '⚡ Schnell' : '⏳ Aufwendig',
      if (!r.hasRecipe) r.source.isEmpty ? 'Rezept fehlt' : '📖 ${r.source}',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 10, color: r.cat.color),
            Expanded(
              child: ListTile(
                title: Text(r.title),
                subtitle: Text(sub),
                trailing: (r.favorite || onCooked != null)
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        if (r.favorite) Icon(Icons.star, color: Colors.amber.shade700),
                        if (onCooked != null)
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onCooked,
                            onLongPress: onCookedPick,
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(Icons.check_circle_outline),
                            ),
                          ),
                      ])
                    : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Recipe> all = [];
  final Set<Cat> cats = {}; // leer = alle Kategorien
  final Set<bool> kinds = {}; // false = Normal, true = Anlass; leer = beides
  final Set<Effort> efforts = {}; // leer = alle
  bool onlyFav = false;
  bool onlyMissing = false;
  bool onlyPaused = false;
  String pantry = '';
  DateTime? lastBackup;
  bool hideBackupHint = false;
  late SharedPreferences prefs;
  List<Map<String, dynamic>> savedRoll = []; // zuletzt gerollte Karten
  bool _loaded = false;
  String _lastFilters = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
  prefs = await SharedPreferences.getInstance();
  loadCatColors(prefs);
  final lb = prefs.getString('lastBackup');
  lastBackup = lb == null ? null : DateTime.tryParse(lb);

  // zuletzt gerollte Karten
  try {
    final rj = prefs.getString('roll');
    if (rj != null) {
      savedRoll = [
        for (final e in jsonDecode(rj) as List) Map<String, dynamic>.from(e as Map)
      ];
    }
  } catch (_) {}

  // zuletzt benutzte Filter
  try {
    final fj = prefs.getString('filters');
    if (fj != null) {
      final m = jsonDecode(fj) as Map<String, dynamic>;
      final catMap = Cat.values.asNameMap();
      final effMap = Effort.values.asNameMap();
      cats.addAll(List<String>.from(m['cats'] ?? []).map((n) => catMap[n]).whereType<Cat>());
      kinds.addAll(List<bool>.from(m['kinds'] ?? []));
      efforts.addAll(
          List<String>.from(m['efforts'] ?? []).map((n) => effMap[n]).whereType<Effort>());
      onlyFav = m['fav'] == true;
    }
  } catch (_) {}

  final raw = prefs.getStringList('recipes') ?? [];
  setState(() {
    all = raw.map((s) => Recipe.fromJson(jsonDecode(s))).toList();
    _loaded = true;
  });
}

void _persistFilters() {
  if (!_loaded) return;
  final s = jsonEncode({
    'cats': [for (final c in cats) c.name],
    'kinds': kinds.toList(),
    'efforts': [for (final e in efforts) e.name],
    'fav': onlyFav,
  });
  if (s == _lastFilters) return;
  _lastFilters = s;
  prefs.setString('filters', s);
}

  Future<void> _save() =>
      prefs.setStringList('recipes', all.map((r) => jsonEncode(r.toJson())).toList());

  bool _matches(Recipe r) =>
      (cats.isEmpty || cats.contains(r.cat)) &&
      (kinds.isEmpty || kinds.contains(r.special)) &&
      (efforts.isEmpty || efforts.contains(r.effort)) &&
      (!onlyFav || r.favorite);

  /// Karten für den Spielautomaten: Filter passt, nicht pausiert
  List<Recipe> get pool => all.where((r) => _matches(r) && !r.paused).toList();

  /// Karten für Listen und Suche: Filter passt (auch pausierte)
  List<Recipe> get listPool => all.where(_matches).toList();

  List<String> get terms => pantry
      .split(RegExp(r'[,\n]'))
      .map((t) => t.trim().toLowerCase())
      .where((t) => t.isNotEmpty)
      .toList();

bool _hit(Recipe r, String t) =>
    r.title.toLowerCase().contains(t) ||
    r.ingredients.any((i) {
      final x = i.toLowerCase();
      return x.contains(t) || (x.length >= 4 && t.contains(x));
    });

int score(Recipe r) => terms.where((t) => _hit(r, t)).length;

/// Wie viele Suchbegriffe im Namen vorkommen (Namenstreffer stehen oben)
int tScore(Recipe r) =>
    terms.where((t) => r.title.toLowerCase().contains(t)).length;

void _markCooked(Recipe r, [DateTime? when]) {
  final prev = r.lastCooked;
  setState(() => r.lastCooked = when ?? DateTime.now());
  _save();
  final label = when == null
      ? 'als heute gekocht markiert'
      : 'als gekocht am ${shortDate(when)} markiert';
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text('"${r.title}" $label'),
      action: SnackBarAction(
        label: 'Rückgängig',
        onPressed: () {
          setState(() => r.lastCooked = prev);
          _save();
        },
      ),
    ));
}

/// Fragt, wann gekocht wurde: Heute / Gestern / Vorgestern / beliebiger Tag
Future<DateTime?> _pickCookedDate() async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final choice = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(title: const Text('Wann gekocht?'), children: [
      SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Heute')),
      SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 1), child: const Text('Gestern')),
      SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 2), child: const Text('Vorgestern')),
      SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, -1), child: const Text('Anderes Datum …')),
    ]),
  );
  if (choice == null) return null;
  if (choice >= 0) return today.subtract(Duration(days: choice));
  if (!mounted) return null;
  return showDatePicker(
    context: context,
    initialDate: today,
    firstDate: today.subtract(const Duration(days: 730)),
    lastDate: today,
  );
}

Future<void> _markCookedOn(Recipe r) async {
  final d = await _pickCookedDate();
  if (d != null) _markCooked(r, d);
}

  bool get needsBackup {
    if (hideBackupHint || all.length < 5) return false;
    return lastBackup == null || DateTime.now().difference(lastBackup!).inDays >= 30;
  }

  Future<void> _backup() async {
    final ok = await exportRecipes(all, full: true);
    if (!ok) return;
    lastBackup = DateTime.now();
    await prefs.setString('lastBackup', lastBackup!.toIso8601String());
    if (mounted) setState(() {});
  }

  Future<void> _edit([Recipe? r]) async {
    final res = await Navigator.push<Recipe>(
        context, MaterialPageRoute(builder: (_) => EditPage(recipe: r)));
    if (res == null) return;
    setState(() {
      final i = all.indexWhere((x) => x.id == res.id);
      if (i >= 0) {
        all[i] = res;
      } else {
        all.add(res);
      }
    });
    await _save();
  }

  /// Rezepttext einfügen, aufteilen, dann in der Bearbeiten-Seite prüfen
  Future<void> _pasteRecipe(Recipe r) async {
    final res = await Navigator.push<Recipe>(
        context, MaterialPageRoute(builder: (_) => PasteRecipePage(recipe: r)));
    if (res != null && mounted) await _edit(res);
  }

  Future<void> _quickType() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuickTypePage(
          all: all,
          onChanged: () {
            setState(() {});
            _save();
          },
        ),
      ),
    );
  }

  Future<void> _manage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ManagePage(
          all: all,
          onChanged: () {
            setState(() {});
            _save();
          },
        ),
      ),
    );
  }

  Future<void> _importFile() async {
    final res = await importRecipes(context, all);
    if (res == null || !mounted) return;
    setState(() => all.addAll(res.fresh));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${res.fresh.length} neu, ${res.filled} Rezepte ergänzt')));
  }

  Future<void> _pickTheme() async {
    final m = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Darstellung'), children: [
        for (final (mode, label) in [
          (ThemeMode.system, 'Wie das System'),
          (ThemeMode.light, 'Hell'),
          (ThemeMode.dark, 'Dunkel'),
        ])
          SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, mode), child: Text(label)),
      ]),
    );
    if (m == null) return;
    themeNotifier.value = m;
    await prefs.setString('theme', m.name);
  }

  void _deleteWithUndo(Recipe r) {
    final idx = all.indexOf(r);
    if (idx < 0) return;
    setState(() => all.removeAt(idx));
    _save();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('"${r.title}" gelöscht'),
        action: SnackBarAction(
          label: 'Rückgängig',
          onPressed: () {
            setState(() => all.insert(min(idx, all.length), r));
            _save();
          },
        ),
      ));
  }

  /// Nach einer Änderung im Detail-Sheet: speichern und Sheet neu öffnen
  void _changed(BuildContext ctx, Recipe r) {
    setState(() {});
    _save();
    Navigator.pop(ctx);
    _open(r);
  }

  void _open(Recipe r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              PopupMenuButton<Cat>(
                tooltip: 'Kategorie ändern',
                onSelected: (c) {
                  r.cat = c;
                  _changed(ctx, r);
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
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 8, backgroundColor: r.cat.color),
                  const SizedBox(width: 8),
                  Text(r.cat.label, style: Theme.of(ctx).textTheme.labelLarge),
                  const Icon(Icons.arrow_drop_down),
                ]),
              ),
              const Spacer(),
              Text(ago(r.lastCooked)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text(r.title, style: Theme.of(ctx).textTheme.headlineSmall)),
              IconButton(
                tooltip: 'Favorit',
                icon: Icon(r.favorite ? Icons.star : Icons.star_border,
                    color: r.favorite ? Colors.amber.shade700 : null),
                onPressed: () {
                  r.favorite = !r.favorite;
                  _changed(ctx, r);
                },
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilterChip(
                avatar: const Icon(Icons.celebration, size: 16),
                label: const Text('Anlass'),
                selected: r.special,
                onSelected: (v) {
                  r.special = v;
                  _changed(ctx, r);
                },
              ),
              for (final e in Effort.values)
                ChoiceChip(
                  avatar: Icon(e.icon, size: 16),
                  label: Text(e.label),
                  selected: r.effort == e,
                  onSelected: (_) {
                    r.effort = e;
                    _changed(ctx, r);
                  },
                ),
              PopupMenuButton<int>(
                onSelected: (d) {
                  r.pausedUntil = d == 0 ? null : DateTime.now().add(Duration(days: d));
                  _changed(ctx, r);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 14, child: Text('2 Wochen pausieren')),
                  const PopupMenuItem(value: 28, child: Text('4 Wochen pausieren')),
                  const PopupMenuItem(value: 56, child: Text('8 Wochen pausieren')),
                  if (r.paused)
                    const PopupMenuItem(value: 0, child: Text('Pause aufheben')),
                ],
                child: Chip(
                  avatar: const Icon(Icons.pause_circle_outline, size: 16),
                  label: Text(r.paused
                      ? 'Pausiert bis ${shortDate(r.pausedUntil!)}'
                      : 'Pausieren'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            if (r.source.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.menu_book, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(r.source)),
              ]),
              const SizedBox(height: 12),
            ],
            if (!r.hasRecipe) ...[
              const Text('Zu dieser Karte gibt es noch kein Rezept.'),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.document_scanner),
                label: const Text('Rezept einlesen (Foto / Text)'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _pasteRecipe(r);
                },
              ),
              const SizedBox(height: 16),
            ],
            if (r.ingredients.isNotEmpty) ...[
              Text('Zutaten', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final i in r.ingredients) Text('• $i'),
              const SizedBox(height: 16),
            ],
            if (r.instructions.isNotEmpty) ...[
              Text('Rezept', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(r.instructions),
              const SizedBox(height: 16),
            ],
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Heute gekocht'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _markCooked(r);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: const Text('Anderer Tag'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _markCookedOn(r);
                },
              ),
            ]),
            if (r.hasRecipe)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('Kochmodus'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final done = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(builder: (_) => CookModePage(recipe: r)));
                    if (done == true && mounted) {
                      setState(() => r.lastCooked = DateTime.now());
                      _save();
                    }
                  },
                ),
              ),
              if (r.ingredients.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Zutaten an Erinnerungen'),
                  onPressed: () => showIngredientExport(ctx, r),
                ),
              ),
            Wrap(spacing: 4, children: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _edit(r);
                  },
                  child: const Text('Bearbeiten')),
              if (r.hasRecipe)
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pasteRecipe(r);
                    },
                    child: const Text('Text hinzufügen')),
              TextButton(onPressed: () => exportRecipes([r]), child: const Text('Teilen')),
              TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _deleteWithUndo(r);
                  },
                  child: const Text('Löschen')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _backupBanner() {
    final days = lastBackup == null ? null : DateTime.now().difference(lastBackup!).inDays;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.save_alt),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                days == null ? 'Noch kein Backup' : 'Letztes Backup: vor $days Tagen',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          const Text('Sichere deine Karten, z. B. in der Dateien-App.'),
          Row(children: [
            TextButton(onPressed: _backup, child: const Text('Jetzt sichern')),
            TextButton(
                onPressed: () => setState(() => hideBackupHint = true),
                child: const Text('Später')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _persistFilters();
    final usePantry = terms.isNotEmpty;
    final missing = all.where((r) => !r.hasRecipe).length;
    final pausedCount = all.where((r) => r.paused).length;

    List<Recipe>? list;
    if (usePantry || onlyMissing || onlyPaused) {
      list = listPool
          .where((r) =>
              (!usePantry || score(r) > 0) &&
              (!onlyMissing || !r.hasRecipe) &&
              (!onlyPaused || r.paused))
          .toList();
      if (usePantry) {
        list.sort((a, b) {
          final t = tScore(b).compareTo(tScore(a));
          if (t != 0) return t;
          final s = score(b).compareTo(score(a));
          return s != 0 ? s : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
      } else {
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      }
    }

    Widget body;
    if (all.isEmpty) {
      body = const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Noch keine Karten. Oben "Karten eintippen" nutzen oder mit + anlegen!',
            textAlign: TextAlign.center),
      ));
    } else if (list == null) {
      body = SlotMachine(
        pool: pool,
        onOpen: _open,
        initialRoll: savedRoll,
        onRollChanged: (roll) => prefs.setString('roll', jsonEncode(roll)),
      );
    } else if (list.isEmpty) {
      body = Center(
          child: Text(usePantry ? 'Nichts mit diesen Zutaten gefunden' : 'Keine passenden Karten'));
    } else {
      body = ListView(padding: const EdgeInsets.only(bottom: 80), children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('✓ antippen = heute gekocht · lang drücken = anderer Tag',
              style: TextStyle(fontSize: 12)),
        ),
        for (final r in list)
          RecipeTile(
            r: r,
            extra: usePantry ? '${score(r)} von ${terms.length} passen' : null,
            onTap: () => _open(r),
            onCooked: () => _markCooked(r),
            onCookedPick: () => _markCookedOn(r),
          ),
      ]);
    }

    final row2 = <Widget>[
      FilterChip(
        avatar: const Icon(Icons.weekend_outlined, size: 16),
        label: const Text('Normal'),
        selected: kinds.contains(false),
        onSelected: (v) => setState(() => v ? kinds.add(false) : kinds.remove(false)),
      ),
      FilterChip(
        avatar: const Icon(Icons.celebration, size: 16),
        label: const Text('Anlass'),
        selected: kinds.contains(true),
        onSelected: (v) => setState(() => v ? kinds.add(true) : kinds.remove(true)),
      ),
      for (final e in Effort.values)
        FilterChip(
          avatar: Icon(e.icon, size: 16),
          label: Text(e.label),
          selected: efforts.contains(e),
          onSelected: (v) => setState(() => v ? efforts.add(e) : efforts.remove(e)),
        ),
      FilterChip(
        avatar: const Icon(Icons.star, size: 16),
        label: const Text('Favoriten'),
        selected: onlyFav,
        onSelected: (v) => setState(() => onlyFav = v),
      ),
      if (missing > 0 || onlyMissing)
        FilterChip(
          avatar: const Icon(Icons.menu_book, size: 16),
          label: Text('Ohne Rezept ($missing)'),
          selected: onlyMissing,
          onSelected: (v) => setState(() => onlyMissing = v),
        ),
      if (pausedCount > 0 || onlyPaused)
        FilterChip(
          avatar: const Icon(Icons.pause_circle_outline, size: 16),
          label: Text('Pausiert ($pausedCount)'),
          selected: onlyPaused,
          onSelected: (v) => setState(() => onlyPaused = v),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('KochKasten'), actions: [
        IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Karten eintippen',
            onPressed: _quickType),
        IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Alle Karten verwalten',
            onPressed: _manage),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'colors') {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ColorsPage()));
              setState(() {});
            } else if (v == 'theme') {
              await _pickTheme();
            } else if (v == 'backup') {
              await _backup();
            } else if (v == 'export') {
              await exportRecipes(all);
            } else if (v == 'import') {
              await _importFile();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'colors', child: Text('Kartenfarben')),
            PopupMenuItem(value: 'theme', child: Text('Darstellung (Hell/Dunkel)')),
            PopupMenuItem(value: 'backup', child: Text('Backup erstellen')),
            PopupMenuItem(value: 'export', child: Text('Zum Teilen exportieren')),
            PopupMenuItem(value: 'import', child: Text('Importieren')),
          ],
        ),
      ]),
      floatingActionButton:
          FloatingActionButton(onPressed: () => _edit(), child: const Icon(Icons.add)),
      body: Column(children: [
        if (needsBackup) _backupBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              FilterChip(
                label: const Text('Alle'),
                selected: cats.isEmpty,
                onSelected: (_) => setState(cats.clear),
              ),
              for (final c in Cat.values)
                FilterChip(
                  avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
                  label: Text(c.label),
                  selected: cats.contains(c),
                  onSelected: (v) => setState(() => v ? cats.add(c) : cats.remove(c)),
                ),
            ]),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final w in row2)
                  Padding(padding: const EdgeInsets.only(right: 8), child: w),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Suchen: Gericht oder Zutat (z.B. Fisch, Karotte)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => pantry = v),
          ),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

class EditPage extends StatefulWidget {
  final Recipe? recipe;
  const EditPage({super.key, this.recipe});
  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  late final title = TextEditingController(text: widget.recipe?.title);
  late final src = TextEditingController(text: widget.recipe?.source);
  late final ing = TextEditingController(text: widget.recipe?.ingredients.join('\n'));
  late final ins = TextEditingController(text: widget.recipe?.instructions);
  late Cat cat = widget.recipe?.cat ?? Cat.fleisch;
  late bool special = widget.recipe?.special ?? false;
  late Effort effort = widget.recipe?.effort ?? Effort.medium;

  Future<void> _scan() async {
    final cur = Recipe(
      id: widget.recipe?.id ?? 'tmp',
      title: title.text.trim(),
      cat: cat,
      ingredients: ing.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      instructions: ins.text.trim(),
      source: src.text.trim(),
      special: special,
      effort: effort,
      favorite: widget.recipe?.favorite ?? false,
      lastCooked: widget.recipe?.lastCooked,
      pausedUntil: widget.recipe?.pausedUntil,
    );
    final res = await Navigator.push<Recipe>(
        context, MaterialPageRoute(builder: (_) => PasteRecipePage(recipe: cur)));
    if (res == null) return;
    setState(() {
      ing.text = res.ingredients.join('\n');
      ins.text = res.instructions;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.recipe == null ? 'Neue Karte' : 'Karte bearbeiten'),
          actions: [
            TextButton(
              onPressed: () {
                if (title.text.trim().isEmpty) return;
                Navigator.pop(
                  context,
                  Recipe(
                    id: widget.recipe?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
                    title: title.text.trim(),
                    cat: cat,
                    ingredients: ing.text
                        .split('\n')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList(),
                    instructions: ins.text.trim(),
                    source: src.text.trim(),
                    special: special,
                    effort: effort,
                    favorite: widget.recipe?.favorite ?? false,
                    lastCooked: widget.recipe?.lastCooked,
                    pausedUntil: widget.recipe?.pausedUntil,
                  ),
                );
              },
              child: const Text('Speichern'),
            ),
          ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Gericht', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [
          for (final c in Cat.values)
            ChoiceChip(
              avatar: CircleAvatar(backgroundColor: c.color, radius: 6),
              label: Text(c.label),
              selected: cat == c,
              onSelected: (_) => setState(() => cat = c),
            ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<Effort>(
          segments: [
            for (final e in Effort.values) ButtonSegment(value: e, label: Text(e.label))
          ],
          selected: {effort},
          onSelectionChanged: (s) => setState(() => effort = s.first),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Für besondere Anlässe'),
          subtitle: const Text('Aus = Normal (Standardwochenende)'),
          value: special,
          onChanged: (v) => setState(() => special = v),
        ),
        TextField(
            controller: src,
            decoration: const InputDecoration(
                labelText: 'Quelle / Kochbuch (z.B. "Schuhbeck, S. 45")',
                border: OutlineInputBorder())),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _scan,
          icon: const Icon(Icons.document_scanner),
          label: const Text('Rezept per Foto / Text einlesen'),
        ),
        const SizedBox(height: 12),
        TextField(
            controller: ing,
            maxLines: 6,
            decoration: const InputDecoration(
                labelText: 'Zutaten (eine pro Zeile)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        TextField(
            controller: ins,
            maxLines: 10,
            decoration: const InputDecoration(labelText: 'Rezept', border: OutlineInputBorder())),
      ]),
    );
  }
}