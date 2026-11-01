import 'dart:io';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

final _picker = ImagePicker();

/// Hohe Auflösung, damit auch kleine Druckschrift erkannt wird
Future<File?> pickPhoto(ImageSource src) async {
  final x = await _picker.pickImage(source: src, imageQuality: 90, maxWidth: 2400);
  return x == null ? null : File(x.path);
}

/// Text aus einem Foto (kostenlos, auf dem Gerät). Gedruckter Text klappt gut.
/// mergeRows = Textstücke auf gleicher Höhe zu einer Zeile verbinden (Tabellen wie "250 g | Mehl").
Future<String> ocrText(File f, {bool mergeRows = false}) async {
  final rec = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final res = await rec.processImage(InputImage.fromFile(f));
    if (!mergeRows) {
      return [
        for (final b in res.blocks)
          for (final l in b.lines) l.text.trim()
      ].where((s) => s.isNotEmpty).join('\n');
    }
    final ls = <TextLine>[for (final b in res.blocks) ...b.lines]
      ..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final rows = <List<TextLine>>[];
    for (final l in ls) {
      if (rows.isNotEmpty) {
        final last = rows.last;
        final cy =
            last.map((e) => e.boundingBox.center.dy).reduce((a, b) => a + b) / last.length;
        final h = last.map((e) => e.boundingBox.height).reduce(max);
        if ((l.boundingBox.center.dy - cy).abs() < h * 0.5) {
          last.add(l);
          continue;
        }
      }
      rows.add([l]);
    }
    return [
      for (final r in rows)
        (r..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left)))
            .map((e) => e.text.trim())
            .join(' ')
    ].where((s) => s.length >= 2).join('\n');
  } finally {
    await rec.close();
  }
}