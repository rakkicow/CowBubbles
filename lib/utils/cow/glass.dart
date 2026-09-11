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

  /// the palette the glass is tinted with: cream paper, brown hide, pink nose
  static const Color cream = Color(0xFFFBEDE4);
  static const Color brown = Color(0xFF3B2418);
  static const Color pink = Color(0xFFF4A9C2);

  /// surface tint. white on a light screen reads as a hole, not as glass;
  /// the cream here is a shade above the page so the panel lifts off it
  static Color tint(bool dark) => dark ? brown : cream;

  /// what the rim and sheen are lit with
  static Color highlight(bool dark) => dark ? cream : Colors.white;

  /// fill alpha
  static double fill(bool dark) => dark ? 0.22 : 0.82;

  /// rim alphas, top vs bottom
  static double rimTop(bool dark) => dark ? 0.34 : 0.95;
  static double rimBottom(bool dark) => dark ? 0.08 : 0.45;

  /// a soft drop under a light panel, so it reads as sitting above the page
  static List<BoxShadow> lift(bool dark) => dark
      ? const []
      : const [BoxShadow(color: Color(0x1A3B2418), blurRadius: 18, offset: Offset(0, 6))];

  /// sheen strength
  static double sheen(bool dark) => dark ? 0.10 : 0.38;
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
    final base = tint ?? GlassTokens.tint(dark);
    final alpha = fillAlpha ?? GlassTokens.fill(dark);

    return CustomPaint(
      foregroundPainter: _RimPainter(
        radius: radius,
        top: GlassTokens.highlight(dark).withOpacity(GlassTokens.rimTop(dark)),
        bottom: GlassTokens.highlight(dark).withOpacity(GlassTokens.rimBottom(dark)),
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: r,
          color: base.withOpacity(alpha),
          boxShadow: GlassTokens.lift(dark),
          // sheen
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.center,
            colors: [
              GlassTokens.highlight(dark).withOpacity(GlassTokens.sheen(dark)),
              GlassTokens.highlight(dark).withOpacity(0),
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
