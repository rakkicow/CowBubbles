import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/ui/facetime_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'album_palette.dart';
import 'glass.dart';
import 'now_playing.dart';
import 'oklch.dart';

/// warp shader, compiled once
class _WarpProgram {
  static Future<ui.FragmentProgram>? _future;
  static ui.FragmentShader? shader;

  static Future<void> load() async {
    _future ??= ui.FragmentProgram.fromAsset('shaders/album_warp.frag');
    try {
      shader ??= (await _future!).fragmentShader();
    } catch (_) {
      // no GL support; falls back to the painter
      shader = null;
    }
  }
}

/// precompile the warp shader
Future<void> warmUpMusicShader() => _WarpProgram.load();

/// reduced motion
bool _reduceMotion(BuildContext context) =>
    MediaQuery.maybeOf(context)?.disableAnimations ?? false;

/// album art background
class MusicBackground extends StatefulWidget {
  final AlbumPalette palette;

  /// small copy; upscaling it is the blur
  final ui.Image? art;

  /// ground laid back over the colour
  final double scrim;

  const MusicBackground({
    super.key,
    required this.palette,
    this.art,
    // ~quarter of the cover's luminance
    this.scrim = 0.42,
  });

  @override
  State<MusicBackground> createState() => _MusicBackgroundState();
}

class _MusicBackgroundState extends State<MusicBackground>
    with TickerProviderStateMixin {
  /// warp time, accumulated not looped
  // painters repaint off this; setState rebuilds the whole subtree
  final ValueNotifier<double> _warpTime = ValueNotifier<double>(0);
  Duration _lastTick = Duration.zero;

  late final Ticker _ticker;

  /// host route, so the warp can idle during the slide
  Animation<double>? _route;

  /// speed pulse, driven by lyric line changes
  double _pulse = 0;
  String? _lastLine;

  static const double _baseSpeed = 1.0;
  static const double _pulseMax = 0.5;
  static const double _pulseDecay = 2.2;

  /// cover cross-fade
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );

  ui.Image? _previous;

  @override
  void initState() {
    super.initState();
    _WarpProgram.load().then((_) {
      if (mounted) setState(() {});
    });
    _ticker = createTicker(_onTick);
    cowMusic.lyricLine.addListener(_onLine);
  }

  // no warp while the page is sliding
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final anim = ModalRoute.of(context)?.animation;
    if (identical(anim, _route)) return;
    _route?.removeStatusListener(_onRouteStatus);
    _route = anim;
    if (anim == null) {
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    anim.addStatusListener(_onRouteStatus);
    _onRouteStatus(anim.status);
  }

  void _onRouteStatus(AnimationStatus status) {
    final settled = status == AnimationStatus.completed;
    if (settled && !_ticker.isActive) {
      _ticker.start();
    } else if (!settled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onLine() {
    final line = cowMusic.lyricLine.value;
    if (line == _lastLine) return;
    _lastLine = line;
    // only a new line pulses
    if (line != null && line.isNotEmpty) _pulse = 1.0;
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.5) return;

    _pulse *= math.exp(-_pulseDecay * dt);
    final speed = _baseSpeed + _pulseMax * _pulse;
    _warpTime.value += dt * speed;
  }

  @override
  void didUpdateWidget(MusicBackground old) {
    super.didUpdateWidget(old);
    if (!identical(old.art, widget.art)) {
      _previous = old.art;
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onRouteStatus);
    _ticker.dispose();
    cowMusic.lyricLine.removeListener(_onLine);
    _fade.dispose();
    _warpTime.dispose();
    super.dispose();
  }

  /// neutral ground, not `colorScheme.surface`
  static Color _ground(bool dark) => dark
      ? const Oklch(0.16, 0.030, 285).toColor()
      : const Oklch(0.985, 0.006, 285).toColor();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ground = _ground(dark);
    final still = _reduceMotion(context);
    final art = widget.art;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: ground),
          AnimatedBuilder(
            animation: _fade,
            builder: (context, _) {
              final t = still ? 0.2 : _warpTime.value;
              final f = still ? 1.0 : Curves.easeInOut.transform(_fade.value);
              if (art == null) {
                return CustomPaint(
                  isComplex: true,
                  willChange: !still,
                  painter: _BlobPainter(
                      colors: widget.palette.normalised(dark: dark),
                      t: t / 30.0),
                );
              }

              final shader = _WarpProgram.shader;
              if (shader != null) {
                return LayoutBuilder(builder: (context, c) {
                  const down = 2.0;
                  return Transform.scale(
                    scale: down,
                    alignment: Alignment.topLeft,
                    // upscaled 2x; lower reads as pixelation
                    filterQuality: FilterQuality.medium,
                    child: SizedBox(
                      width: c.maxWidth / down,
                      height: c.maxHeight / down,
                      child: CustomPaint(
                        isComplex: true,
                        willChange: !still,
                        painter: _WarpPainter(
                          shader: shader,
                          art: art,
                          time: _warpTime,
                          still: still,
                          scrim: widget.scrim,
                          ground: ground,
                        ),
                      ),
                    ),
                  );
                });
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  // outgoing cover keeps drifting underneath
                  if (_previous != null && f < 1)
                    CustomPaint(
                      isComplex: true,
                      willChange: true,
                      painter: _ArtFieldPainter(art: _previous!, t: t / 30.0),
                    ),
                  Opacity(
                    opacity: f,
                    child: CustomPaint(
                      isComplex: true,
                      willChange: !still,
                      painter: _ArtFieldPainter(art: art, t: t / 30.0),
                    ),
                  ),
                ],
              );
            },
          ),
          // scrim, for legibility
          ColoredBox(color: ground.withOpacity(widget.scrim)),
        ],
      ),
    );
  }
}

/// warp shader pass
class _WarpPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image art;
  final ValueNotifier<double> time;
  final bool still;
  final double scrim;
  final Color ground;

  _WarpPainter({
    required this.shader,
    required this.art,
    required this.time,
    required this.still,
    required this.scrim,
    required this.ground,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setImageSampler(0, art)
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, still ? 6.0 : time.value)
      // indices must match uniform order in album_warp.frag
      ..setFloat(3, 2.0) // twist
      ..setFloat(4, 1.30) // saturation
      ..setFloat(5, scrim)
      ..setFloat(6, ground.red / 255.0)
      ..setFloat(7, ground.green / 255.0)
      ..setFloat(8, ground.blue / 255.0)
      ..setFloat(9, art.width.toDouble())
      ..setFloat(10, art.height.toDouble());
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  // time arrives via `repaint:`
  @override
  bool shouldRepaint(_WarpPainter old) =>
      old.art != art || old.scrim != scrim || old.still != still;
}

/// shader fallback: the cover drawn at several rotations
class _ArtFieldPainter extends CustomPainter {
  final ui.Image art;
  final double t;

  _ArtFieldPainter({required this.art, required this.t});

  /// layer rates, mutually irrational so they never re-align
  static const _layers = [
    (speed: 1.00, scale: 1.00, opacity: 1.00, phase: 0.0, wobble: 1.0),
    (speed: -0.61, scale: 1.34, opacity: 0.60, phase: 2.2, wobble: 0.73),
    (speed: 0.37, scale: 1.76, opacity: 0.42, phase: 4.1, wobble: 1.31),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    const tau = 2 * math.pi;
    final src =
        Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble());
    // oversized so rotation never exposes a corner
    final cover = math.max(size.width, size.height) * 2.1;
    final paint = Paint()
      ..filterQuality = FilterQuality.high
      ..isAntiAlias = true;

    canvas.clipRect(Offset.zero & size);

    for (final l in _layers) {
      final angle = t * tau * l.speed + l.phase;
      final breathe = 1 + 0.14 * math.sin(t * tau * l.wobble + l.phase);
      final side = cover * l.scale * breathe;
      final dx = size.width / 2 +
          size.width * 0.18 * math.sin(t * tau * l.wobble * 0.8 + l.phase);
      final dy = size.height / 2 +
          size.height * 0.16 * math.cos(t * tau * l.wobble * 1.1 + l.phase);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(angle);
      paint.color = Color.fromRGBO(255, 255, 255, l.opacity);
      canvas.drawImageRect(art, src,
          Rect.fromCenter(center: Offset.zero, width: side, height: side), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ArtFieldPainter old) => old.t != t || old.art != art;
}

/// fallback for a title with no cover
class _BlobPainter extends CustomPainter {
  final List<Color> colors;
  final double t;

  _BlobPainter({required this.colors, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    const tau = 2 * math.pi;
    for (var i = 0; i < colors.length; i++) {
      final a = 0.9 + i * 0.37;
      final b = 1.3 + i * 0.29;
      final phase = i * 1.7;
      final cx = size.width * (0.5 + 0.42 * math.sin(tau * t * a + phase));
      final cy = size.height * (0.42 + 0.40 * math.cos(tau * t * b + phase));
      final radius =
          size.width * (0.52 + 0.14 * math.sin(tau * t * (0.7 + i * 0.2)));
      final c = colors[i];
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            radius,
            [
              c.withOpacity(0.95),
              c.withOpacity(0.45),
              c.withOpacity(0.14),
              c.withOpacity(0.0),
            ],
            const [0.0, 0.34, 0.62, 1.0],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.t != t;
}

/// equaliser bars
// no true amplitude: players refuse audio capture
class MusicBars extends StatefulWidget {
  final Color color;
  final List<Color> colors;
  final double height;
  final bool playing;

  const MusicBars({
    super.key,
    required this.color,
    this.colors = const [],
    this.height = 17,
    this.playing = true,
  });

  @override
  State<MusicBars> createState() => _MusicBarsState();
}

class _MusicBarsState extends State<MusicBars>
    with SingleTickerProviderStateMixin {
  // one controller, five rates
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 10000),
  );

  static const _tracks = <(double, List<(double, double)>)>[
    (1.70, [(0.0, 0.35), (0.30, 0.85), (0.55, 0.45), (0.80, 0.95), (1.0, 0.35)]),
    (2.10, [(0.0, 0.80), (0.25, 0.40), (0.50, 1.00), (0.75, 0.30), (1.0, 0.80)]),
    (1.45, [(0.0, 0.55), (0.35, 1.00), (0.65, 0.25), (1.0, 0.55)]),
    (2.30, [(0.0, 0.40), (0.20, 0.90), (0.45, 0.55), (0.70, 1.00), (1.0, 0.40)]),
    (1.85, [(0.0, 0.70), (0.30, 0.30), (0.60, 0.90), (0.85, 0.45), (1.0, 0.70)]),
  ];

  /// eased between keyframes
  static double _sample(List<(double, double)> keys, double t) {
    for (var i = 0; i < keys.length - 1; i++) {
      final (s0, v0) = keys[i];
      final (s1, v1) = keys[i + 1];
      if (t >= s0 && t <= s1) {
        final local = (t - s0) / (s1 - s0);
        return v0 + (v1 - v0) * Curves.easeInOut.transform(local);
      }
    }
    return keys.last.$2;
  }

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(MusicBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      // hold shape, don't snap flat
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) {
      return Icon(Icons.graphic_eq_rounded, size: 18, color: widget.color);
    }
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final elapsed = _c.value * 10.0;
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _tracks.length; i++) ...[
                if (i > 0) const SizedBox(width: 2),
                Builder(builder: (context) {
                  final (period, keys) = _tracks[i];
                  final phase = (elapsed % period) / period;
                  final h = widget.height * _sample(keys, phase);
                  final c = widget.colors.isEmpty
                      ? widget.color
                      : widget.colors[i % widget.colors.length];
                  return Container(
                    width: 2.5,
                    height: h,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(color: c.withOpacity(0.45), blurRadius: 6)
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// interval dots
class IntervalDots extends StatefulWidget {
  final Color color;
  final Duration start;
  final Duration end;

  /// dot diameter, ~a third of the font size
  final double size;

  const IntervalDots({
    super.key,
    required this.color,
    required this.start,
    required this.end,
    this.size = 8,
  });

  @override
  State<IntervalDots> createState() => _IntervalDotsState();
}

class _IntervalDotsState extends State<IntervalDots> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final span = (widget.end - widget.start).inMilliseconds.toDouble();
    final elapsed = (cowMusic.position - widget.start).inMilliseconds.toDouble();
    final p = span <= 0 ? 1.0 : (elapsed / span).clamp(0.0, 1.0);
    final reduce = _reduceMotion(context);

    // swell and fade into the next line
    final outMs = math.min(600.0, span * 0.2);
    final out = span <= 0 ? 0.0 : ((elapsed - (span - outMs)) / outMs).clamp(0.0, 1.0);
    final outEase = Curves.easeInOut.transform(out);
    final groupScale = (1 + 0.12 * outEase) *
        (reduce ? 1 : 1 + 0.03 * math.sin(elapsed / 1000 * 2 * math.pi / 2.6));
    final groupAlpha = 1 - outEase;

    final d = widget.size;
    return Opacity(
      opacity: groupAlpha,
      child: Transform.scale(
        scale: groupScale,
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: d * 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (i) {
              // each dot fills its own third
              final fill = Curves.easeInOut.transform(((p * 3) - i).clamp(0.0, 1.0));
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: d * 0.35),
                child: Transform.scale(
                  scale: 0.8 + 0.2 * fill,
                  child: Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      color: widget.color.withOpacity(0.32 + 0.68 * fill),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// typing dots, for a song with no line to show
class LyricDots extends StatefulWidget {
  final Color color;
  const LyricDots({super.key, required this.color});

  @override
  State<LyricDots> createState() => _LyricDotsState();
}

class _LyricDotsState extends State<LyricDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion(context)) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: _dot(widget.color, 0),
          ),
        ),
      );
    }
    return SizedBox(
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            // each dot trails the last
            final phase = ((_c.value * 3) - i * 0.55).clamp(0.0, 1.0);
            final lift = (phase < 0.5 ? phase : 1 - phase) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.translate(
                offset: Offset(0, -lift * 4),
                child: _dot(widget.color, lift),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _dot(Color color, double lift) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: color.withOpacity(0.55 + lift * 0.45),
          shape: BoxShape.circle,
        ),
      );
}

/// now playing strip, also the transport
class NowPlayingChip extends StatelessWidget {
  final String title;
  final String artist;
  final ui.Image? art;
  final List<Color> waveColors;
  final bool playing;
  final VoidCallback? onTap;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  /// hold to peek at lyrics
  final VoidCallback? onHoldStart;
  final ValueChanged<double>? onHoldMove;
  final VoidCallback? onHoldEnd;

  const NowPlayingChip({
    super.key,
    required this.title,
    required this.artist,
    this.art,
    this.waveColors = const [],
    this.playing = true,
    this.onTap,
    this.onNext,
    this.onPrevious,
    this.onHoldStart,
    this.onHoldMove,
    this.onHoldEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;

    // painted outside the Material tree; text would render underlined
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // left advances, right goes back
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) onNext?.call();
          if (v > 200) onPrevious?.call();
        },
        onLongPressStart: onHoldStart == null ? null : (_) => onHoldStart!(),
        onLongPressMoveUpdate: onHoldMove == null ? null : (d) => onHoldMove!(d.offsetFromOrigin.dy),
        onLongPressEnd: onHoldEnd == null ? null : (_) => onHoldEnd!(),
        onLongPressCancel: onHoldEnd,
        child: Semantics(
          button: true,
          label: playing
              ? 'Now playing $title by $artist. Tap to pause, swipe for the next track, hold for lyrics.'
              : 'Paused: $title by $artist. Tap to play, hold for lyrics.',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            // same glass as the header
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GlassTokens.card),
              child: BackdropFilter(
                filter: ui.ImageFilter.compose(
                  outer: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  inner: ColorFilter.matrix(dark ? darkMatrix : lightMatrix),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(GlassTokens.fill(dark)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.center,
                      colors: [
                        Colors.white.withOpacity(GlassTokens.sheen(dark)),
                        Colors.white.withOpacity(0),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(GlassTokens.card),
                    border: Border.all(color: Colors.white.withOpacity(GlassTokens.rimBottom(dark)), width: 1),
                  ),
                  child: Row(
                    children: [
                      // concentric: 22 less the 6px inset
                      if (art != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: RawImage(image: art, fit: BoxFit.cover),
                          ),
                        )
                      else
                        Icon(Icons.music_note_rounded, size: 22, color: onSurface),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'SFPro',
        fontFamilyFallback: const ['BricolageGrotesque'],
                                fontVariations: const [FontVariation('wght', 600)],
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: onSurface,
                              ),
                            ),
                            if (artist.isNotEmpty)
                              Text(
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'SFPro',
        fontFamilyFallback: const ['BricolageGrotesque'],
                                  fontVariations: const [FontVariation('wght', 500)],
                                  fontSize: 11.5,
                                  color: onSurface.withOpacity(0.65),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _TransportGlyph(
                        playing: playing,
                        colors: waveColors,
                        fallback: onSurface.withOpacity(0.75),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// bars while playing, play mark while paused
class _TransportGlyph extends StatelessWidget {
  final bool playing;
  final List<Color> colors;
  final Color fallback;

  const _TransportGlyph({
    required this.playing,
    required this.colors,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final still = _reduceMotion(context);
    final child = playing
        ? MusicBars(
            key: const ValueKey('bars'),
            color: fallback,
            colors: colors,
            playing: true,
          )
        : _PlayMark(key: const ValueKey('play'), colors: colors, fallback: fallback);

    return SizedBox(
      width: 22,
      height: 18,
      child: Center(
        child: still
            ? child
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (w, anim) => ScaleTransition(
                  scale: anim,
                  child: FadeTransition(opacity: anim, child: w),
                ),
                child: child,
              ),
      ),
    );
  }
}

/// play mark in the artwork's colours
class _PlayMark extends StatelessWidget {
  final List<Color> colors;
  final Color fallback;

  const _PlayMark({super.key, required this.colors, required this.fallback});

  @override
  Widget build(BuildContext context) {
    final stops = colors.length >= 2 ? colors : [fallback, fallback];
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: stops,
      ).createShader(rect),
      child: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
    );
  }
}
