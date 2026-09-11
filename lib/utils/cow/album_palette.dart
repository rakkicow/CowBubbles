import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor, HSVColor;

import 'oklch.dart';

/// dominant colours from album art
class AlbumPalette {
  final List<Color> colors;
  final Color dominant;
  final double averageLightness;

  const AlbumPalette({
    required this.colors,
    required this.dominant,
    required this.averageLightness,
  });

  bool get isDark => averageLightness < 0.5;

  /// raw rgba, 4 bytes per pixel, not encoded
  factory AlbumPalette.fromPixels(
    Uint8List pixels, {
    int maxColors = 5,
    int stride = 4,
  }) {
    // 5 bits per channel
    const bits = 5;
    const shift = 8 - bits;
    final bins = <int, _Bin>{};

    final step = 4 * stride;
    for (var i = 0; i + 3 < pixels.length; i += step) {
      final a = pixels[i + 3];
      if (a < 128) continue;
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];

      final key = ((r >> shift) << (bits * 2)) |
          ((g >> shift) << bits) |
          (b >> shift);
      (bins[key] ??= _Bin()).add(r, g, b);
    }

    if (bins.isEmpty) {
      return const AlbumPalette(
        colors: [Color(0xFF6B6B7B)],
        dominant: Color(0xFF6B6B7B),
        averageLightness: 0.42,
      );
    }

    final scored = bins.values.toList()
      ..sort((x, y) => y.score.compareTo(x.score));

    // keep colours far enough apart
    final picked = <_Bin>[];
    for (final bin in scored) {
      if (picked.length >= maxColors) break;
      final tooClose = picked.any((p) => p.distanceTo(bin) < 60);
      if (!tooClose) picked.add(bin);
    }
    if (picked.isEmpty) picked.add(scored.first);

    final totalWeight = picked.fold<int>(0, (s, b) => s + b.count);
    final lightness = picked.fold<double>(
          0,
          (s, b) => s + b.relativeLuminance * b.count,
        ) /
        math.max(totalWeight, 1);

    return AlbumPalette(
      colors: picked.map((b) => b.color).toList(),
      dominant: picked.first.color,
      averageLightness: lightness,
    );
  }

  /// hue only, at even lightness and chroma
  List<Color> normalised({required bool dark, double alpha = 1.0}) {
    return colors.map((c) {
      final hue = _hueOf(c);
      return Oklch(dark ? 0.55 : 0.78, dark ? 0.16 : 0.13, hue).toColor(alpha);
    }).toList();
  }

  /// bubble colour, at signature lightness and chroma
  Color bubbleColor({required bool dark}) {
    final hue = _hueOf(dominant);
    return Oklch(dark ? 0.70 : 0.66, 0.18, hue).toColor();
  }

  /// most vivid colour, not [dominant]
  Color popColor({required bool dark}) {
    Color best = dominant;
    var bestScore = -1.0;
    for (final c in colors) {
      final sat = HSVColor.fromColor(c).saturation;
      final midness = 1 - (2 * HSLColor.fromColor(c).lightness - 1).abs();
      final score = sat * (0.4 + 0.6 * midness);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    final sat = HSVColor.fromColor(best).saturation;
    final chroma = 0.17 + 0.07 * sat;
    return Oklch(dark ? 0.70 : 0.66, chroma, _hueOf(best)).toColor();
  }

  /// the cover's own colours, clamped for legibility
  List<Color> display({required bool dark, double alpha = 1.0}) {
    final lo = dark ? 0.46 : 0.28;
    final hi = dark ? 0.78 : 0.58;
    return colors.map((c) {
      final hsl = HSLColor.fromColor(c);
      final l = hsl.lightness.clamp(lo, hi);
      // saturation floor, so muted covers still show
      final sat = hsl.saturation < 0.18 ? 0.18 : hsl.saturation;
      return hsl.withLightness(l).withSaturation(sat).toColor().withOpacity(alpha);
    }).toList();
  }

  static double _hueOf(Color c) {
    final r = c.red / 255, g = c.green / 255, b = c.blue / 255;
    final maxV = math.max(r, math.max(g, b));
    final minV = math.min(r, math.min(g, b));
    final d = maxV - minV;
    if (d == 0) return 0;
    double h;
    if (maxV == r) {
      h = ((g - b) / d) % 6;
    } else if (maxV == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    // srgb hue, not oklch; monotonic enough
    return (h * 60) % 360;
  }
}

class _Bin {
  int count = 0;
  int rSum = 0, gSum = 0, bSum = 0;

  void add(int r, int g, int b) {
    count++;
    rSum += r;
    gSum += g;
    bSum += b;
  }

  int get r => rSum ~/ count;
  int get g => gSum ~/ count;
  int get b => bSum ~/ count;

  Color get color => Color.fromARGB(255, r, g, b);

  double get relativeLuminance =>
      (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;

  /// population, weighted toward saturation
  double get score {
    final maxV = math.max(r, math.max(g, b));
    final minV = math.min(r, math.min(g, b));
    final sat = maxV == 0 ? 0.0 : (maxV - minV) / maxV;
    // favour mid lightness
    final l = relativeLuminance;
    final midness = 1 - (2 * l - 1).abs();
    return count * (0.35 + sat) * (0.5 + 0.5 * midness);
  }

  double distanceTo(_Bin other) {
    final dr = (r - other.r).toDouble();
    final dg = (g - other.g).toDouble();
    final db = (b - other.b).toDouble();
    return math.sqrt(dr * dr + dg * dg + db * db);
  }
}
