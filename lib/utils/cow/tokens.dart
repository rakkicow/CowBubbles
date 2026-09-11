import 'package:flutter/material.dart';

// shared design tokens; radii live in GlassTokens

/// spacing, multiples of 4
class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// motion, springy but short
class Motion {
  static const Duration instant = Duration(milliseconds: 120);
  static const Duration quick = Duration(milliseconds: 220);
  static const Duration base = Duration(milliseconds: 340);
  static const Duration slow = Duration(milliseconds: 520);

  /// overshoot, then settle
  static const Curve spring = Cubic(0.22, 1.4, 0.36, 1.0);
  static const Curve enter = Cubic(0.16, 1.0, 0.30, 1.0);
  static const Curve exit = Cubic(0.5, 0.0, 0.75, 0.0);

  /// reduced motion
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// type, bundled not fetched
class CowType {
  static TextStyle display(BuildContext context) =>
      TextStyle(fontFamily: 'BricolageGrotesque', 
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.05,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle title(BuildContext context) =>
      TextStyle(fontFamily: 'BricolageGrotesque', 
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle name(BuildContext context) =>
      TextStyle(fontFamily: 'BricolageGrotesque', 
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle body(BuildContext context) => TextStyle(fontFamily: 'InstrumentSans', 
        fontSize: 15.5,
        height: 1.35,
        letterSpacing: -0.1,
        color: Theme.of(context).colorScheme.onSurface,
      );

  static TextStyle secondary(BuildContext context) =>
      TextStyle(fontFamily: 'InstrumentSans', 
        fontSize: 14,
        height: 1.3,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
      );

  static TextStyle label(BuildContext context) => TextStyle(fontFamily: 'InstrumentSans', 
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
      );
}

/// press feedback
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.972,
    this.semanticLabel,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final target = _down && !Motion.reduce(context) ? widget.scale : 1.0;
    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: target,
          duration: Motion.instant,
          curve: Motion.enter,
          child: widget.child,
        ),
      ),
    );
  }
}
