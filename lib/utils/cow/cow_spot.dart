import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// cow-spot blob, deterministic from [seed]
class CowSpot extends ShapeBorder {
  final int seed;
  final int points;

  /// lobe deviation from a circle
  final double wobble;

  const CowSpot({this.seed = 0, this.points = 7, this.wobble = 0.20});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      buildPath(rect, seed: seed, points: points, wobble: wobble);

  static Path buildPath(Rect rect,
      {int seed = 0, int points = 7, double wobble = 0.20}) {
    final rnd = _Lcg(seed * 7919 + 13);
    final cx = rect.center.dx, cy = rect.center.dy;
    // widest lobe just reaches the rect
    final norm = 1.0 / (1.0 + wobble / 2);
    final rx = rect.width / 2 * norm, ry = rect.height / 2 * norm;

    final pts = <Offset>[];
    for (var i = 0; i < points; i++) {
      final base = (i / points) * 2 * math.pi;
      final angle = base + (rnd.nextDouble() - 0.5) * (math.pi / points);
      final r = 1.0 - wobble / 2 + rnd.nextDouble() * wobble;
      pts.add(Offset(cx + rx * r * math.cos(angle), cy + ry * r * math.sin(angle)));
    }

    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final p0 = pts[(i - 1 + n) % n], p1 = pts[i];
      final p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => CowSpot(seed: seed, points: points, wobble: wobble);

  /// stable seed per handle, fnv-1a
  static int seedFor(String? key) {
    if (key == null || key.isEmpty) return 0;
    var h = 0x811c9dc5;
    for (final u in key.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }
}

/// fixed lcg, so shapes never shift with the sdk
class _Lcg {
  int _s;
  _Lcg(int seed) : _s = seed & 0xFFFFFFFF;
  double nextDouble() {
    _s = (_s * 1664525 + 1013904223) & 0xFFFFFFFF;
    return _s / 4294967296.0;
  }
}
