import 'dart:math' as math;
import 'dart:ui';

/// perceptual colour in oklch
class Oklch {
  final double l; // lightness 0..1
  final double c; // chroma, ~0..0.37 in srgb
  final double h; // hue, degrees

  const Oklch(this.l, this.c, this.h);

  Oklch withLightness(double v) => Oklch(v, c, h);
  Oklch withChroma(double v) => Oklch(l, v, h);
  Oklch withHue(double v) => Oklch(l, c, v);

  Oklch lighten(double amount) => Oklch((l + amount).clamp(0.0, 1.0), c, h);
  Oklch darken(double amount) => Oklch((l - amount).clamp(0.0, 1.0), c, h);
  Oklch mute(double factor) => Oklch(l, c * factor, h);

  Color toColor([double opacity = 1.0]) {
    final hRad = h * math.pi / 180.0;
    final a = c * math.cos(hRad);
    final b = c * math.sin(hRad);

    // oklab -> lms
    final lp = l + 0.3963377774 * a + 0.2158037573 * b;
    final mp = l - 0.1055613458 * a - 0.0638541728 * b;
    final sp = l - 0.0894841775 * a - 1.2914855480 * b;

    final lc = lp * lp * lp;
    final mc = mp * mp * mp;
    final sc = sp * sp * sp;

    // lms -> linear srgb
    final r = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc;
    final g = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc;
    final bl = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc;

    return Color.fromARGB(
      (opacity.clamp(0.0, 1.0) * 255).round(),
      _encode(r),
      _encode(g),
      _encode(bl),
    );
  }

  /// linear srgb -> 8-bit, gamut-clipped
  static int _encode(double v) {
    final e = v <= 0.0031308
        ? 12.92 * v
        : 1.055 * math.pow(v.clamp(0.0, 1.0), 1 / 2.4) - 0.055;
    return (e.clamp(0.0, 1.0) * 255).round();
  }
}
