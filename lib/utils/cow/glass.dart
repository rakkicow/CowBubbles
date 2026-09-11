import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// liquid glass surfaces
// blur is expensive: GlassFill for repeated surfaces

class GlassTokens {
  /// radii
  static const double capsule = 999;
  static const double panel = 28;
  static const double card = 22;
  static const double chip = 16;

  static const double blur = 24;

  /// fill alpha
  static double fill(bool dark) => dark ? 0.10 : 0.55;

  /// rim alphas, top vs bottom
  static double rimTop(bool dark) => dark ? 0.34 : 0.85;
  static double rimBottom(bool dark) => dark ? 0.08 : 0.35;

  /// sheen strength
  static double sheen(bool dark) => dark ? 0.14 : 0.45;
}

/// full glass: backdrop, fill, rim, sheen
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final double? blur;

  const Glass({
    super.key,
    required this.child,
    this.radius = GlassTokens.panel,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.blur,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: blur ?? GlassTokens.blur,
          sigmaY: blur ?? GlassTokens.blur,
        ),
        child: GlassFill(
          radius: radius,
          padding: padding,
          tint: tint,
          child: child,
        ),
      ),
    );
  }
}

/// glass without the backdrop blur
class GlassFill extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? tint;

  /// fill alpha override
  final double? fillAlpha;

  const GlassFill({
    super.key,
    required this.child,
    this.radius = GlassTokens.panel,
    this.padding = EdgeInsets.zero,
    this.tint,
    this.fillAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final r = BorderRadius.circular(radius);
    final base = tint ?? (dark ? Colors.white : Colors.white);
    final alpha = fillAlpha ?? GlassTokens.fill(dark);

    return CustomPaint(
      foregroundPainter: _RimPainter(
        radius: radius,
        top: Colors.white.withOpacity(GlassTokens.rimTop(dark)),
        bottom: Colors.white.withOpacity(GlassTokens.rimBottom(dark)),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: r,
          color: base.withOpacity(alpha),
          // sheen
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.center,
            colors: [
              Colors.white.withOpacity(GlassTokens.sheen(dark)),
              Colors.white.withOpacity(0),
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 1px rim, brighter at the top
// a Border can't vary colour along its length
class _RimPainter extends CustomPainter {
  final double radius;
  final Color top;
  final Color bottom;

  _RimPainter({required this.radius, required this.top, required this.bottom});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [top, bottom],
        ),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.top != top || old.bottom != bottom;
}

/// capsule glass button
class GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? tint;
  final String? semanticLabel;

  const GlassButton({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    this.tint,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: GlassFill(
            radius: GlassTokens.capsule,
            padding: padding,
            tint: tint,
            child: child,
          ),
        ),
      );
}
