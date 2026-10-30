import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

void loadCatColors(SharedPreferences p) {
  final raw = p.getString('catRgb');
  if (raw == null) return;
  final m = Map<String, dynamic>.from(jsonDecode(raw));
  for (final c in Cat.values) {
    if (m[c.name] != null) catRgb[c] = List<int>.from(m[c.name]);
  }
}

Future<void> saveCatColors(SharedPreferences p) => p.setString(
    'catRgb', jsonEncode({for (final e in catRgb.entries) e.key.name: e.value}));

const _presets = <List<int>>[
  [229, 57, 53], [216, 27, 96], [142, 36, 170], [94, 53, 177],
  [63, 81, 181], [30, 136, 229], [3, 169, 244], [0, 172, 193],
  [0, 137, 123], [67, 160, 71], [124, 179, 66], [205, 220, 57],
  [253, 216, 53], [255, 179, 0], [251, 140, 0], [244, 81, 30],
  [121, 85, 72], [117, 117, 117], [255, 248, 225], [255, 255, 255],
];

class ColorsPage extends StatefulWidget {
  const ColorsPage({super.key});
  @override
  State<ColorsPage> createState() => _ColorsPageState();
}

class _ColorsPageState extends State<ColorsPage> {
  Future<void> _pick(Cat c) async {
    var rgb = [...(catRgb[c] ?? c.defRgb)];
    final res = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          title: Text(c.label),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in _presets)
                  GestureDetector(
                    onTap: () => set(() => rgb = [...p]),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color.fromARGB(255, p[0], p[1], p[2]),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              for (var i = 0; i < 3; i++)
                Row(children: [
                  SizedBox(width: 16, child: Text('RGB'[i])),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 255,
                      value: rgb[i].toDouble(),
                      onChanged: (v) => set(() => rgb[i] = v.round()),
                    ),
                  ),
                ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, <int>[]), child: const Text('Standard')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(ctx, rgb), child: const Text('OK')),
          ],
        );
      }),
    );
    if (res == null) return;
    if (res.isEmpty) {
      catRgb.remove(c);
    } else {
      catRgb[c] = res;
    }
    await saveCatColors(await SharedPreferences.getInstance());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Kartenfarben')),
        body: ListView(children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Stell die Farben so ein, wie deine Karteikarten aussehen.'),
          ),
          for (final c in Cat.values)
            ListTile(
              leading: CircleAvatar(backgroundColor: c.color),
              title: Text(c.label),
              trailing: const Icon(Icons.edit),
              onTap: () => _pick(c),
            ),
        ]),
      );
}