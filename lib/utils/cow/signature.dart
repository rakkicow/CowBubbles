import 'dart:ui' show Brightness, Color;

import 'oklch.dart';

/// conversation colour, from the handle
// 12-step wheel, L and C fixed so all twelve weigh the same
class Signature {
  final double hue;
  final Brightness brightness;

  const Signature(this.hue, this.brightness);

  static const int _steps = 12;
  static const double _wheelOffset = 18.0;

  factory Signature.forHandle(String? handle, Brightness brightness) {
    final key = (handle == null || handle.isEmpty) ? '?' : handle;
    // fnv-1a: stable across runs, unlike hashCode
    int hash = 0x811c9dc5;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return Signature(
        _wheelOffset + (hash % _steps) * (360.0 / _steps), brightness);
  }

  bool get _dark => brightness == Brightness.dark;

  /// full strength
  Color get base => Oklch(_dark ? 0.70 : 0.66, 0.18, hue).toColor();

  /// gradient partner
  Color get gradientEnd => Oklch(_dark ? 0.64 : 0.60, 0.19, hue + 22).toColor();

  /// on base
  Color get onBase => Oklch(_dark ? 0.16 : 0.99, 0.02, hue).toColor();

  /// wash
  Color get wash => Oklch(_dark ? 0.26 : 0.95, 0.05, hue).toColor();

  /// accent text, on the ground
  Color get accentText => Oklch(_dark ? 0.80 : 0.48, 0.15, hue).toColor();

  List<Color> get gradient => [base, gradientEnd];
}
