import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// superellipse border
class Squircle extends ShapeBorder {
  /// higher n = squarer
  final double n;
  final double radiusFactor;

  const Squircle({this.n = 4.4, this.radiusFactor = 1.0});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = Path();
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final a = rect.width / 2 * radiusFactor;
    final b = rect.height / 2 * radiusFactor;
    const samples = 96;
    final exp = 2 / n;

    for (var i = 0; i <= samples; i++) {
      final t = (i / samples) * 2 * math.pi;
      final ct = math.cos(t);
      final st = math.sin(t);
      final x = cx + a * _signedPow(ct, exp);
      final y = cy + b * _signedPow(st, exp);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  static double _signedPow(double v, double e) =>
      v.sign * math.pow(v.abs(), e).toDouble();

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => Squircle(n: n, radiusFactor: radiusFactor * t);
}

/// corners only; [Squircle] goes stadium on a wide rect
class SquircleRect extends ShapeBorder {
  final double radius;
  final double n;

  const SquircleRect({this.radius = 26, this.n = 4.4});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    final exp = 2 / n;
    const steps = 14;
    final path = Path();

    // consecutive corners sweep in opposite directions
    void corner(double cx, double cy, double sx, double sy, double t0, double t1) {
      for (var i = 0; i <= steps; i++) {
        final t = t0 + (t1 - t0) * (i / steps);
        path.lineTo(
          cx + sx * r * _sp(math.cos(t), exp),
          cy + sy * r * _sp(math.sin(t), exp),
        );
      }
    }

    const q = math.pi / 2;
    path.moveTo(rect.left + r, rect.top);
    path.lineTo(rect.right - r, rect.top);
    corner(rect.right - r, rect.top + r, 1, -1, q, 0);
    path.lineTo(rect.right, rect.bottom - r);
    corner(rect.right - r, rect.bottom - r, 1, 1, 0, q);
    path.lineTo(rect.left + r, rect.bottom);
    corner(rect.left + r, rect.bottom - r, -1, 1, q, 0);
    path.lineTo(rect.left, rect.top + r);
    corner(rect.left + r, rect.top + r, -1, -1, 0, q);
    return path..close();
  }

  static double _sp(double v, double e) =>
      v.sign * math.pow(v.abs(), e).toDouble();

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => SquircleRect(radius: radius * t, n: n);
}
