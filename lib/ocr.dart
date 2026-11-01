import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

final _picker = ImagePicker();

/// Hohe Auflösung, damit auch kleine Druckschrift erkannt wird
Future<File?> pickPhoto(ImageSource src) async {
  final x = await _picker.pickImage(source: src, imageQuality: 90, maxWidth: 2400);
  return x == null ? null : File(x.path);
}

class _Ln {
  final String text;
  final Rect box;
  final int block; // Nummer des ML-Kit-Blocks
  final int idx; // Zeile innerhalb des Blocks
  _Ln(this.text, this.box, this.block, this.idx);
  double get left => box.left;
  double get right => box.right;
  double get top => box.top;
  double get cy => box.center.dy;
  double get h => box.height;
}

typedef _Parsed = ({List<String> ing, List<String> steps});

Future<List<_Ln>> _readLines(File f) async {
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final res = await rec.processImage(InputImage.fromFile(f));
    final out = <_Ln>[];
    for (var i = 0; i < res.blocks.length; i++) {
      final ls = res.blocks[i].lines;
      for (var j = 0; j < ls.length; j++) {
        final t = ls[j].text.trim();
        if (t.isNotEmpty) out.add(_Ln(t, ls[j].boundingBox, i, j));
      }
    }
    return _upright(out);
  } finally {
    await rec.close();
  }
}

/// iPhone-Fotos liegen intern oft quer. ML Kit liest den Text richtig, liefert die
/// Koordinaten aber im gedrehten Bild. Hier werden sie zurückgedreht.
List<_Ln> _upright(List<_Ln> ls) {
  final wide = ls.where((l) => l.text.length >= 6).toList();
  if (wide.length < 3) return ls;
  // Normale Textzeilen sind breiter als hoch. Sonst sind die Koordinaten gedreht.
  final ratio = _median([for (final l in wide) l.box.width / max(1.0, l.box.height)]);
  if (ratio >= 1) return ls;

  // Richtung: Wandern die Folgezeilen eines Blocks nach rechts (+x) oder links (-x)?
  final byBlock = <int, List<_Ln>>{};
  for (final l in ls) {
    byBlock.putIfAbsent(l.block, () => []).add(l);
  }
  var vote = 0;
  for (final b in byBlock.values) {
    b.sort((a, c) => a.idx.compareTo(c.idx));
    for (var i = 1; i < b.length; i++) {
      final dx = b[i].box.center.dx - b[i - 1].box.center.dx;
      final dy = b[i].box.center.dy - b[i - 1].box.center.dy;
      if (dx.abs() > dy.abs()) vote += dx > 0 ? 1 : -1;
    }
  }
  final down = vote >= 0; // iPhone Hochformat: Folgezeilen = größeres x
  return [
    for (final l in ls)
      _Ln(
        l.text,
        down
            ? Rect.fromLTRB(-l.box.bottom, l.box.left, -l.box.top, l.box.right)
            : Rect.fromLTRB(l.box.top, -l.box.right, l.box.bottom, -l.box.left),
        l.block,
        l.idx,
      ),
  ];
}

/// Roher Text in der Reihenfolge, wie ML Kit ihn liefert (Fallback)
Future<String> ocrText(File f) async =>
    (await _readLines(f)).map((l) => l.text).join('\n');

/// Layout-bewusstes Einlesen einer Kochbuchseite.
/// Liefert Text in der Form "Zutaten / … / Zubereitung / 1. … / 2. …".
Future<String> ocrRecipe(File f) async {
  final lines = await _readLines(f);
  if (lines.isEmpty) return '';
  final r = _layout(lines);
  if (r == null || (r.ing.isEmpty && r.steps.isEmpty)) {
    return lines.map((l) => l.text).join('\n');
  }
  final b = StringBuffer();
  if (r.ing.isNotEmpty) {
    b.writeln('Zutaten');
    for (final i in r.ing) {
      b.writeln(i);
    }
  }
  if (r.steps.isNotEmpty) {
    b.writeln('Zubereitung');
    for (var i = 0; i < r.steps.length; i++) {
      b.writeln('${i + 1}. ${r.steps[i]}');
    }
  }
  return b.toString().trimRight();
}

// ---------- Hilfsfunktionen ----------

String _clean(String s) =>
    s.replaceAll(RegExp(r'\s*\|\s*'), ', ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Zeilen verbinden, Silbentrennung am Zeilenende reparieren ("Frühlings-" + "zwiebeln")
String _join(String a, String b) {
  if (a.endsWith('-') && b.isNotEmpty && b[0] != b[0].toUpperCase()) {
    return a.substring(0, a.length - 1) + b;
  }
  return '$a $b';
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

// "500 g …", "1 Zwiebel", "½ TL …", aber nicht "1. Brate …" (Schritt-Nummer)
final _amountRe = RegExp(r'^(?!\d+[.)]\s)(\d|[½¼¾])');

final _metaRe = RegExp(
    r'^(für\s+\d+\s*(portionen|personen)|portionen\s*:|kitchen\s*time|essbar|zubereitungszeit|pro\s+portion|\d+\s*(portionen|personen)$)',
    caseSensitive: false);

final _stopRe = RegExp(
    r'^(tipps?\b|unser\s+tipp|variationen?\b|zubehör\b|einstellung\b|hinweis\b|nährwerte\b|automatikprogramm\b|manuell\b)',
    caseSensitive: false);

bool _isMeta(String t) {
  final s = t.trim();
  if (_metaRe.hasMatch(s)) return true;
  if (s.length < 50 && RegExp(r'kcal|\bkj\b|\bkh\b', caseSensitive: false).hasMatch(s)) {
    return true;
  }
  // kurze GROSSBUCHSTABEN-Etiketten wie "SCHNELL & EASY"
  return s == s.toUpperCase() && RegExp(r'[A-ZÄÖÜ]').hasMatch(s) && s.length <= 24;
}

List<List<_Ln>> _rowsOf(List<_Ln> col) {
  final s = [...col]..sort((a, b) => a.top.compareTo(b.top));
  final rows = <List<_Ln>>[];
  for (final l in s) {
    if (rows.isNotEmpty) {
      final last = rows.last;
      final cy = last.map((e) => e.cy).reduce((a, b) => a + b) / last.length;
      final h = last.map((e) => e.h).reduce(max);
      if ((l.cy - cy).abs() < h * 0.5) {
        last.add(l);
        continue;
      }
    }
    rows.add([l]);
  }
  for (final r in rows) {
    r.sort((a, b) => a.left.compareTo(b.left));
  }
  return rows;
}

String _rowText(List<_Ln> r) => _clean(r.map((e) => e.text).join(' '));
double _rowCy(List<_Ln> r) => r.map((e) => e.cy).reduce((a, b) => a + b) / r.length;

// ---------- Zutatenspalte ----------

List<String> _ingredientsFrom(List<_Ln> col) {
  final texts = <String>[];
  final cys = <double>[];
  for (final r in _rowsOf(col)) {
    final t = _rowText(r);
    if (t.isEmpty || _isMeta(t) || RegExp(r'^\d{2,3}$').hasMatch(t)) continue;
    if (_stopRe.hasMatch(t)) break;
    texts.add(t);
    cys.add(_rowCy(r));
  }
  final pitch = _median([for (var i = 1; i < cys.length; i++) cys[i] - cys[i - 1]]);
  final out = <String>[];
  for (var i = 0; i < texts.length; i++) {
    final t = texts[i];
    // Fortsetzung einer umgebrochenen Zutat: keine Menge am Anfang und
    // (Zeile davor endet mit Komma ODER klein geschrieben und eng darunter)
    final tight = i > 0 && pitch > 0 && (cys[i] - cys[i - 1]) < pitch * 0.85;
    final prevComma = out.isNotEmpty && out.last.endsWith(',');
    final lower = RegExp(r'^[a-zäöüß]').hasMatch(t);
    if (out.isNotEmpty && !_amountRe.hasMatch(t) && (prevComma || (tight && lower))) {
      out[out.length - 1] = _join(out.last, t);
    } else {
      out.add(t);
    }
  }
  return out.map(_fixUnit).toList();
}

/// "1TL" -> "1 TL", "500g" -> "500 g"
String _fixUnit(String s) => s.replaceFirstMapped(
    RegExp(r'^(\d+(?:[.,]\d+)?)(TL|EL|Tl|El|kg|ml|cl|dl|g|l|Dose|Dosen|Prise|Bund|Msp)\b'),
    (m) => '${m[1]} ${m[2]}');

// ---------- Zubereitungsspalte ----------

(int, String)? _marker(String t) {
  final m = RegExp(r'^(\d{1,2})(?:\s*[.)]\s*|\s+|$)(.*)$').firstMatch(t);
  if (m == null) return null;
  return (int.parse(m[1]!), (m[2] ?? '').trim());
}

List<String> _stepsFrom(List<_Ln> col) {
  final texts = <String>[];
  final cys = <double>[];
  for (final r in _rowsOf(col)) {
    final t = _rowText(r);
    if (t.isEmpty) continue;
    if (_stopRe.hasMatch(t)) break;
    if (_isMeta(t) || RegExp(r'^\d{2,3}$').hasMatch(t)) continue;
    texts.add(t);
    cys.add(_rowCy(r));
  }
  if (texts.isEmpty) return [];
  final pitch = _median([for (var i = 1; i < cys.length; i++) cys[i] - cys[i - 1]]);

  // Sind die Schritte nummeriert? (mindestens 1 und 2 in Folge)
  var e = 1;
  var found = 0;
  for (final t in texts) {
    final m = _marker(t);
    if (m != null && m.$1 == e) {
      found++;
      e++;
    }
  }
  final numbered = found >= 2;

  final steps = <String>[];
  var cur = '';
  void flush() {
    if (cur.trim().isNotEmpty) steps.add(cur.trim());
    cur = '';
  }

  var expect = 1;
  for (var i = 0; i < texts.length; i++) {
    final t = texts[i];
    if (numbered) {
      final m = _marker(t);
      if (m != null && m.$1 == expect) {
        flush();
        expect++;
        cur = m.$2;
        continue;
      }
    } else {
      final newPara = i == 0 || (pitch > 0 && cys[i] - cys[i - 1] > pitch * 1.45);
      if (newPara) flush();
    }
    cur = cur.isEmpty ? t : _join(cur, t);
  }
  flush();
  return steps;
}

// ---------- Seitenaufbau erkennen ----------

_Parsed? _layout(List<_Ln> all) {
  final minL = all.map((l) => l.left).reduce(min);
  final maxR = all.map((l) => l.right).reduce(max);
  final width = max(1.0, maxR - minL);
  final medH = _median(all.map((l) => l.h).toList());
  final byTop = [...all]..sort((a, b) => a.top.compareTo(b.top));

  _Ln? zut, zub;
  for (final l in byTop) {
    final t = l.text.trim();
    if (t.length > 30) continue;
    if (zut == null && RegExp(r'^zutaten\b', caseSensitive: false).hasMatch(t)) zut = l;
    if (zub == null && RegExp(r'^(zubereitung|anleitung)\b', caseSensitive: false).hasMatch(t)) {
      zub = l;
    }
  }

  final z1 = zut, z2 = zub;
  if (z1 != null && z2 != null) {
    final _Parsed res;
    if ((z1.left - z2.left).abs() > 0.15 * width) {
      // Überschriften nebeneinander: zwei Spalten
      final leftH = z1.left < z2.left ? z1 : z2;
      final rightH = z1.left < z2.left ? z2 : z1;
      final split = rightH.left - 0.04 * width;
      final leftCol = all.where((l) => l.top > leftH.top + 2 && l.left < split).toList();
      final rightCol = all.where((l) => l.top > rightH.top + 2 && l.left >= split).toList();
      final ingLeft = identical(leftH, z1);
      res = (
        ing: _ingredientsFrom(ingLeft ? leftCol : rightCol),
        steps: _stepsFrom(ingLeft ? rightCol : leftCol),
      );
    } else {
      // Überschriften untereinander
      final first = z1.top < z2.top ? z1 : z2;
      final second = z1.top < z2.top ? z2 : z1;
      final between =
          all.where((l) => l.top > first.top + 2 && l.top < second.top - 2).toList();
      final after = all.where((l) => l.top > second.top + 2).toList();
      final ingFirst = identical(first, z1);
      res = (
        ing: _ingredientsFrom(ingFirst ? between : after),
        steps: _stepsFrom(ingFirst ? after : between),
      );
    }
    if (res.ing.isNotEmpty || res.steps.isNotEmpty) return res;
  }
  return _headless(all, width, medH);
}

/// Seiten ohne (erkannte) Überschriften "Zutaten"/"Zubereitung"
_Parsed? _headless(List<_Ln> all, double width, double medH) {
  // A) Zutaten als Fließtext mit "|" (z. B. "300 g Mehl | 4 Eier | …")
  final byBlock = <int, List<_Ln>>{};
  for (final l in all) {
    byBlock.putIfAbsent(l.block, () => []).add(l);
  }
  List<_Ln>? pipe;
  var best = 2;
  for (final b in byBlock.values) {
    final txt = b.map((e) => e.text).join(' ');
    final n = '|'.allMatches(txt).length;
    if (n > best && !RegExp(r'kcal|portion', caseSensitive: false).hasMatch(txt)) {
      best = n;
      pipe = b;
    }
  }
  final p = pipe;
  if (p != null) {
    final pb = [...p]..sort((a, b) => a.top.compareTo(b.top));
    var joined = '';
    for (final l in pb) {
      final t = l.text.trim();
      joined = joined.isEmpty ? t : _join(joined, t);
    }
    final ing = joined.split('|').map(_clean).where((s) => s.isNotEmpty).toList();
    final bottom = pb.map((l) => l.box.bottom).reduce(max);
    final rest = all.where((l) => l.block != p.first.block && l.top > bottom - 2).toList();
    return (ing: ing, steps: _stepsFrom(rest));
  }

  // B) Zwei Spalten ohne Überschriften: Zutaten links (Zeilen mit Mengenangabe),
  //    Zubereitung rechts (lange Zeilen)
  final minL = all.map((l) => l.left).reduce(min);
  final rows = _rowsOf(all);
  final cand = rows
      .where((r) => _amountRe.hasMatch(_rowText(r)) && r.first.left < minL + 0.4 * width)
      .toList();
  if (cand.length < 3) return null;
  final ingLeft = _median(cand.map((r) => r.first.left).toList());
  final firstTop = cand.first.map((e) => e.top).reduce(min);
  final longLines = all
      .where((l) =>
          l.top >= firstTop - 3 * medH &&
          l.left > ingLeft + 0.15 * width &&
          l.text.length >= 40)
      .toList();
  if (longLines.isEmpty) return null;
  final stepLeft = longLines.map((l) => l.left).reduce(min);
  final split = (ingLeft + stepLeft) / 2;
  final contentTop = firstTop - 3 * medH;
  final leftCol = all.where((l) => l.top >= contentTop && l.left < split).toList();
  final rightCol = all.where((l) => l.top >= contentTop && l.left >= split).toList();
  return (ing: _ingredientsFrom(leftCol), steps: _stepsFrom(rightCol));
}