import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';

class IndexCardView extends StatelessWidget {
  final Recipe r;
  const IndexCardView(this.r, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      decoration: BoxDecoration(
        color: Color.lerp(Colors.white, r.cat.color, 0.45),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(blurRadius: 3, offset: Offset(0, 2), color: Colors.black38)
        ],
      ),
      child: CustomPaint(
        painter: _RulesPainter(),
        child: Stack(children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
                child: Text(
                  r.title,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
          if (r.favorite)
            Positioned(
              top: 3,
              right: 4,
              child: Icon(Icons.star, size: 14, color: Colors.amber.shade700),
            ),
        ]),
      ),
    );
  }
}

class _RulesPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final red = Paint()
      ..color = const Color(0x99E53935)
      ..strokeWidth = 1.5;
    final blue = Paint()
      ..color = const Color(0x55448AFF)
      ..strokeWidth = 1;
    final top = s.height * 0.2;
    c.drawLine(Offset(0, top), Offset(s.width, top), red);
    for (var y = top + s.height * 0.16; y < s.height; y += s.height * 0.16) {
      c.drawLine(Offset(0, y), Offset(s.width, y), blue);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Reel {
  final List<Recipe> cards;
  final FixedExtentScrollController ctrl;
  Recipe? result;
  bool held = false;
  _Reel(this.cards, {int start = 0})
      : ctrl = FixedExtentScrollController(initialItem: start);
}

class SlotMachine extends StatefulWidget {
  final List<Recipe> pool;
  final void Function(Recipe) onOpen;

  /// Zuletzt gerollter Stand: pro Walze {'id': Karten-ID oder null, 'held': bool}
  final List<Map<String, dynamic>> initialRoll;
  final void Function(List<Map<String, dynamic>>) onRollChanged;

  const SlotMachine({
    super.key,
    required this.pool,
    required this.onOpen,
    required this.initialRoll,
    required this.onRollChanged,
  });

  @override
  State<SlotMachine> createState() => _SlotMachineState();
}

class _SlotMachineState extends State<SlotMachine> {
  static const double itemH = 110; // Kartenhöhe auf der Walze
  final rnd = Random();
  List<_Reel> reels = [];
  bool spinning = false;

  @override
  void initState() {
    super.initState();
    _buildReels(restore: true);
  }

  void _buildReels({bool restore = false}) {
    final n = min(3, widget.pool.length); // Anzahl Walzen
    final list = <_Reel>[];
    for (var i = 0; i < n; i++) {
      final cards = [...widget.pool]..shuffle(rnd);
      var start = 0;
      Recipe? res;
      var held = false;
      if (restore && i < widget.initialRoll.length) {
        final id = widget.initialRoll[i]['id'];
        final idx = cards.indexWhere((r) => r.id == id);
        if (idx >= 0) {
          start = idx;
          res = cards[idx];
          held = widget.initialRoll[i]['held'] == true;
        }
      }
      list.add(_Reel(cards, start: start)
        ..result = res
        ..held = held);
    }
    reels = list;
    spinning = false;
  }

  /// Aktuellen Stand der Walzen weitergeben (wird dann gespeichert)
  void _emit() {
    if (!mounted) return;
    widget.onRollChanged([
      for (final r in reels) {'id': r.result?.id, 'held': r.held}
    ]);
  }

  @override
  void didUpdateWidget(SlotMachine old) {
    super.didUpdateWidget(old);
    final a = old.pool, b = widget.pool;
    var same = a.length == b.length;
    for (var i = 0; same && i < a.length; i++) {
      same = identical(a[i], b[i]);
    }
    if (!same) {
      final oldReels = reels;
      _buildReels();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in oldReels) {
          r.ctrl.dispose();
        }
        _emit();
      });
    }
  }

  @override
  void dispose() {
    for (final r in reels) {
      r.ctrl.dispose();
    }
    super.dispose();
  }

  /// Gewichtete Ziehung ohne Zurücklegen: je länger nicht gekocht, desto wahrscheinlicher,
  /// Favoriten dreifach. Karten mit gleichem Namen werden nur einmal gezogen.
  List<Recipe> _pick(int n, Set<Recipe> exclude) {
    String key(Recipe r) => r.title.trim().toLowerCase();
    final seen = exclude.map(key).toSet();
    final p = widget.pool.where((r) => !seen.contains(key(r))).toList();
    final out = <Recipe>[];
    for (var i = 0; i < n && p.isNotEmpty; i++) {
      final w = p
          .map((r) =>
              (1 + (r.lastCooked == null ? 60 : DateTime.now().difference(r.lastCooked!).inDays)) *
              (r.favorite ? 3 : 1))
          .toList();
      var x = rnd.nextInt(w.reduce((a, b) => a + b));
      var k = 0;
      while (x >= w[k]) {
        x -= w[k];
        k++;
      }
      final pick = p.removeAt(k);
      out.add(pick);
      p.removeWhere((r) => key(r) == key(pick));
    }
    return out;
  }

  Future<void> _spin() async {
    if (spinning || reels.isEmpty) return;
    final held = <Recipe>{
      for (final r in reels)
        if (r.held && r.result != null) r.result!
    };
    final free = reels.where((r) => !r.held).toList();
    final picks = _pick(free.length, held);
    setState(() {
      spinning = true;
      for (final r in free) {
        r.result = null;
      }
    });
    try {
      final futures = <Future>[];
      for (var i = 0; i < picks.length; i++) {
        final reel = free[i];
        final L = reel.cards.length;
        final target = reel.cards.indexOf(picks[i]);
        final c = reel.ctrl.selectedItem;
        final cycles = ((24 + i * 10) / L).ceil(); // volle Umdrehungen
        final steps = cycles * L + ((target - c) % L);
        futures.add(reel.ctrl
            .animateToItem(c + steps,
                duration: Duration(milliseconds: 1600 + i * 600),
                curve: Curves.easeOutCubic)
            .then((_) {
          if (!mounted) return;
          setState(() => reel.result = picks[i]);
          HapticFeedback.mediumImpact();
        }));
      }
      await Future.wait(futures);
    } catch (_) {}
    if (mounted) setState(() => spinning = false);
    _emit();
  }

  Widget _reelView(_Reel reel) {
    return Column(children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final r = reel.result;
          if (r != null && !spinning) widget.onOpen(r);
        },
        child: SizedBox(
          height: 240,
          child: Stack(children: [
            ListWheelScrollView.useDelegate(
              key: ObjectKey(reel),
              controller: reel.ctrl,
              physics: const NeverScrollableScrollPhysics(),
              itemExtent: itemH,
              diameterRatio: 1.7,
              perspective: 0.003,
              overAndUnderCenterOpacity: 0.55,
              childDelegate: ListWheelChildLoopingListDelegate(
                  children: [for (final c in reel.cards) IndexCardView(c)]),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  height: itemH,
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                        horizontal: BorderSide(color: Colors.amber.shade400, width: 2)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
      TextButton.icon(
        onPressed: (spinning || reel.result == null)
            ? null
            : () {
                setState(() => reel.held = !reel.held);
                _emit();
              },
        icon: Icon(reel.held ? Icons.lock : Icons.lock_open, size: 16),
        label: Text(reel.held ? 'Gehalten' : 'Halten'),
        style: TextButton.styleFrom(
            foregroundColor: Colors.white, disabledForegroundColor: Colors.white38),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (reels.isEmpty) {
      return const Center(child: Text('Keine Karten für diese Auswahl'));
    }
    final started = reels.any((r) => r.result != null);
    return ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 80), children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          decoration: BoxDecoration(
              color: const Color(0xFF263238), borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.all(8),
          child: Row(children: [for (final r in reels) Expanded(child: _reelView(r))]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: spinning ? null : _spin,
          icon: const Icon(Icons.casino),
          label: Text(started ? 'Nochmal drehen' : 'Ziehen!'),
        ),
      ),
      if (started)
        const Center(
          child: Text('Karte antippen zum Öffnen', style: TextStyle(fontSize: 12)),
        ),
    ]);
  }
}