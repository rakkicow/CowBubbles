import 'dart:async';
import 'dart:ui' as ui;

import 'package:bluebubbles/helpers/ui/facetime_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
import 'music_background.dart';
import 'lyrics.dart';
import 'now_playing.dart';
import 'tokens.dart';

enum LyricSheetMode { closed, peek, full }

/// drives the sheet from the chip's hold gesture
class LyricSheetController extends ChangeNotifier {
  LyricSheetMode _mode = LyricSheetMode.closed;
  LyricSheetMode get mode => _mode;
  bool get isOpen => _mode != LyricSheetMode.closed;

  /// hold travel
  double _holdDy = 0;
  double get holdDy => _holdDy;

  /// travel to commit
  static const double commitDistance = 90;

  void hold() {
    if (_mode != LyricSheetMode.closed) return;
    _mode = LyricSheetMode.peek;
    _holdDy = 0;
    HapticFeedback.mediumImpact();
    notifyListeners();
  }

  void holdMove(double dy) {
    if (_mode != LyricSheetMode.peek) return;
    // sub-pixel jitter, skip
    if ((dy - _holdDy).abs() < 1 && dy < commitDistance) return;
    _holdDy = dy;
    if (dy >= commitDistance) {
      _mode = LyricSheetMode.full;
      // unfocus; not on the peek, it reflows the conversation
      FocusManager.instance.primaryFocus?.unfocus();
      HapticFeedback.heavyImpact();
    }
    notifyListeners();
  }

  /// released
  void release() {
    if (_mode == LyricSheetMode.peek) close();
  }

  /// holdDy kept on purpose, so the stretch decays with the close
  void close() {
    if (_mode == LyricSheetMode.closed) return;
    _mode = LyricSheetMode.closed;
    notifyListeners();
  }
}

/// warm the SF Pro variations before the first hold
void warmUpLyricType() {
  for (final size in const [24.0, 34.0]) {
    final p = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: 'moo', style: _LyricListState.styleFor(size, Colors.white)),
    )..layout();
    p.dispose();
  }
}

/// the lyric sheet and the conversation it opens over
class LyricSheet extends StatefulWidget {
  final LyricSheetController controller;

  /// null when nothing is playing
  final NowPlaying? track;
  final bool playing;

  /// top of the peek
  final double peekTop;

  /// the conversation
  final Widget child;

  const LyricSheet({
    super.key,
    required this.controller,
    required this.track,
    required this.playing,
    required this.peekTop,
    required this.child,
  });

  @override
  State<LyricSheet> createState() => _LyricSheetState();
}

class _LyricSheetState extends State<LyricSheet> with TickerProviderStateMixin {
  /// closed to peek
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: Motion.slow,
    reverseDuration: Motion.quick,
  );

  /// spring out here; AnimationController clamps to 0..1
  late final Animation<double> _openCurve = CurvedAnimation(
    parent: _open,
    curve: Motion.spring,
    reverseCurve: Curves.easeIn,
  );

  /// peek to full
  late final AnimationController _full = AnimationController(
    vsync: this,
    duration: Motion.slow,
    reverseDuration: Motion.base,
  );

  late final Animation<double> _fullCurve = CurvedAnimation(
    parent: _full,
    curve: Motion.enter,
    reverseCurve: Curves.easeInOutCubic,
  );

  /// inactive-line blur; ramps back once the panel rests
  late final AnimationController _soft = AnimationController(
    vsync: this,
    duration: Motion.quick,
    value: 1,
  );

  LyricSheetMode _lastMode = LyricSheetMode.closed;

  /// chrome hides until a tap
  bool _chromeShown = false;
  Timer? _chromeTimer;
  Offset? _pointerDown;

  void _revealChrome() {
    if (!mounted) return;
    setState(() => _chromeShown = true);
    _chromeTimer?.cancel();
    _chromeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _chromeShown = false);
    });
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _lastMode = widget.controller.mode;
    _open.value = widget.controller.isOpen ? 1 : 0;
    _full.value = widget.controller.mode == LyricSheetMode.full ? 1 : 0;
    _open.addStatusListener(_onMotion);
    _full.addStatusListener(_onMotion);
  }

  @override
  void didUpdateWidget(LyricSheet old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _lastMode = LyricSheetMode.closed;
      _sync();
    }
  }

  void _onMotion(AnimationStatus _) {
    final moving = _open.isAnimating || _full.isAnimating;
    if (moving) {
      _soft.value = 0;
    } else {
      _soft.forward();
    }
  }

  void _sync() {
    if (!mounted) return;
    final mode = widget.controller.mode;
    if (mode == LyricSheetMode.closed) {
      _chromeShown = false;
      _chromeTimer?.cancel();
    }
    // hold moves notify too; only a mode change drives the controllers
    if (mode == _lastMode) return;
    _lastMode = mode;

    if (Motion.reduce(context)) {
      _open.value = mode == LyricSheetMode.closed ? 0 : 1;
      _full.value = mode == LyricSheetMode.full ? 1 : 0;
      return;
    }
    switch (mode) {
      case LyricSheetMode.closed:
        if (_full.value > 0) {
          // back through the peek, or the centred line gets chopped
          _full.reverse().then((_) {
            if (mounted && widget.controller.mode == LyricSheetMode.closed) _open.reverse();
          });
        } else {
          _open.reverse();
        }
      case LyricSheetMode.peek:
        _full.reverse();
        _open.forward();
      case LyricSheetMode.full:
        _open.forward();
        _full.forward();
    }
    _onMotion(AnimationStatus.forward);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _open.dispose();
    _full.dispose();
    _soft.dispose();
    _chromeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_openCurve, _fullCurve, widget.controller]),
      builder: (context, _) {
        final open = _openCurve.value;
        final ease = _fullCurve.value.clamp(0.0, 1.0);
        final track = widget.track;
        return Stack(
          fit: StackFit.expand,
          children: [
            // no layer at the ends, only during the hand-off
            IgnorePointer(
              ignoring: ease > 0.5,
              child: Opacity(opacity: 1 - ease, child: widget.child),
            ),
            if (track != null && (open > 0 || ease > 0)) _sheet(context, track, open, ease),
          ],
        );
      },
    );
  }

  Widget _sheet(BuildContext context, NowPlaying track, double open, double ease) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduce = Motion.reduce(context);
    final ink = dark ? Colors.white : const Color(0xFF17151C);

    // the peek grows under the finger
    final stretch = (widget.controller.holdDy / LyricSheetController.commitDistance).clamp(0.0, 1.0);
    final peekHeight = (size.height - widget.peekTop) * 0.46;
    final peekWidth = size.width - 24;

    final left = ui.lerpDouble(12, 0, ease)!;
    final top = ui.lerpDouble(widget.peekTop + 4, 0, ease)!;
    final width = size.width - 2 * left;
    final targetHeight = ui.lerpDouble(peekHeight, size.height, ease)!;
    // top pinned, height follows open, overshoot included
    final height = (targetHeight + 48 * stretch * (1 - ease)) * open.clamp(0.0, 1.2);
    final radius = ui.lerpDouble(GlassTokens.panel, 0, ease)!;

    // peek glass fades with ease
    final glass = 1 - ease;
    final fillAlpha = (dark ? 0.42 : 0.55) * glass;
    final rimAlpha = GlassTokens.rimBottom(dark) * glass;
    final sheenAlpha = GlassTokens.sheen(dark) * 0.6 * glass;

    Widget surface = Container(
      decoration: BoxDecoration(
        color: (dark ? Colors.black : Colors.white).withOpacity(fillAlpha),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.center,
          colors: [
            Colors.white.withOpacity(sheenAlpha),
            Colors.white.withOpacity(0),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(rimAlpha), width: 1),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Opacity(
        opacity: open.clamp(0.0, 1.0),
        child: _content(
          context,
          track,
          ink,
          ease,
          pad,
          peekSize: Size(peekWidth, peekHeight),
          fullSize: size,
        ),
      ),
    );

    if (glass > 0.01 && !reduce) {
      final m = dark ? darkMatrix : lightMatrix;
      const id = <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
      final matrix = List<double>.generate(20, (i) => ui.lerpDouble(id[i], m[i], glass)!);
      surface = BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ImageFilter.blur(sigmaX: 30 * glass, sigmaY: 30 * glass),
          inner: ColorFilter.matrix(matrix),
        ),
        child: surface,
      );
    }

    // condenses out of the chip, on the spring
    final settle = ui.lerpDouble(0.96, 1.0, open.clamp(0.0, 1.0))!;
    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Transform.scale(
        scale: settle,
        alignment: Alignment.topCenter,
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: surface,
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    NowPlaying track,
    Color ink,
    double ease,
    EdgeInsets pad, {
    required Size peekSize,
    required Size fullSize,
  }) {
    final isFull = ease > 0.5;
    final chrome = isFull && _chromeShown;

    // two lists, laid out once each; centres match, so they cross-fade
    const ratio = 34 / 24;
    Widget lines;
    if (track.lyrics.isEmpty) {
      lines = _NoLyrics(ink: ink);
    } else {
      final peekList = _fixed(
        peekSize,
        _LyricList(
          key: const ValueKey('peek'),
          track: track,
          full: false,
          ink: ink,
          width: peekSize.width,
          height: peekSize.height,
          soft: _soft,
        ),
      );
      final fullList = _fixed(
        fullSize,
        _LyricList(
          key: const ValueKey('full'),
          track: track,
          full: true,
          ink: ink,
          width: fullSize.width,
          height: fullSize.height,
          soft: _soft,
        ),
      );
      lines = Stack(
        fit: StackFit.expand,
        children: [
          if (ease < 1)
            Opacity(
              opacity: 1 - ease,
              child: Transform.scale(
                scale: ui.lerpDouble(1, ratio, ease)!,
                alignment: Alignment.center,
                child: peekList,
              ),
            ),
          if (ease > 0)
            Opacity(
              opacity: ease,
              child: Transform.scale(
                scale: ui.lerpDouble(1 / ratio, 1, ease)!,
                alignment: Alignment.center,
                child: fullList,
              ),
            ),
        ],
      );
    }

    // chrome floats over the lines; Listener, since the lines own the tap
    lines = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _pointerDown = e.position,
      onPointerUp: (e) {
        final down = _pointerDown;
        if (isFull && down != null && (e.position - down).distance < 12) _revealChrome();
      },
      child: lines,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        lines,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _chromeLayer(
            visible: chrome,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 500) widget.controller.close();
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, pad.top + 10, 16, 6),
                child: Row(
                  children: [
                    GlassButton(
                      semanticLabel: 'Close lyrics',
                      onTap: widget.controller.close,
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close_rounded, size: 22, color: ink),
                    ),
                    const SizedBox(width: 14),
                    if (track.art != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: RawImage(image: track.art, fit: BoxFit.cover),
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'SFPro',
        fontFamilyFallback: const ['BricolageGrotesque'],
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              fontVariations: const [FontVariation('wght', 700)],
                              letterSpacing: -0.3,
                              color: ink,
                            ),
                          ),
                          if (track.artist.isNotEmpty)
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'SFPro',
        fontFamilyFallback: const ['BricolageGrotesque'],
                                fontVariations: const [FontVariation('wght', 500)],
                                fontSize: 14,
                                color: ink.withOpacity(0.7),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _chromeLayer(
            visible: chrome,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, pad.bottom + 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GlassButton(
                    semanticLabel: 'Previous track',
                    onTap: cowMusic.previous,
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.skip_previous_rounded, size: 30, color: ink),
                  ),
                  const SizedBox(width: 18),
                  GlassButton(
                    semanticLabel: widget.playing ? 'Pause' : 'Play',
                    onTap: cowMusic.playPause,
                    padding: const EdgeInsets.all(16),
                    child: Icon(
                      widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 38,
                      color: ink,
                    ),
                  ),
                  const SizedBox(width: 18),
                  GlassButton(
                    semanticLabel: 'Next track',
                    onTap: cowMusic.next,
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.skip_next_rounded, size: 30, color: ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// child at exactly [size], centred
  Widget _fixed(Size size, Widget child) {
    return Center(
      child: OverflowBox(
        alignment: Alignment.center,
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
        child: child,
      ),
    );
  }

  /// chrome, hit-testable only while visible
  Widget _chromeLayer({required bool visible, required Widget child}) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.base,
        curve: Curves.easeOut,
        // using the chrome restarts the fade timer
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerUp: (_) => _revealChrome(),
          child: child,
        ),
      ),
    );
  }
}

class _NoLyrics extends StatelessWidget {
  final Color ink;
  const _NoLyrics({required this.ink});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          'No synced lyrics for this song.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SFPro',
        fontFamilyFallback: const ['BricolageGrotesque'],
            fontSize: 20,
            fontWeight: FontWeight.w700,
            fontVariations: const [FontVariation('wght', 700)],
            color: ink.withOpacity(0.55),
          ),
        ),
      ),
    );
  }
}

/// the lines, measured up front so the scroll target is known
class _LyricList extends StatefulWidget {
  final NowPlaying track;
  final bool full;
  final Color ink;

  /// fixed box, never animated
  final double width;
  final double height;

  /// inactive-line blur, 0..1
  final Animation<double> soft;

  const _LyricList({
    super.key,
    required this.track,
    required this.full,
    required this.ink,
    required this.width,
    required this.height,
    required this.soft,
  });

  @override
  State<_LyricList> createState() => _LyricListState();
}

class _LyricListState extends State<_LyricList> {
  late ScrollController _scroll;
  Timer? _timer;
  int _active = -1;

  /// hands off while the user scrolls
  DateTime? _handsOffUntil;

  List<double> _tops = const [];
  List<double> _heights = const [];

  /// rows: lines and intervals
  List<LyricRow> _rows = const [];

  static const double _side = 22;

  /// swell of the current line
  double get _swell => widget.full ? 0.10 : 0.06;

  /// lyric type; weight as a variation, or it comes out synthetic bold
  static TextStyle styleFor(double size, Color ink) => TextStyle(
        fontFamily: 'SFPro',
        fontFamilyFallback: const ['BricolageGrotesque'],
        fontSize: size,
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation('wght', 700), FontVariation('opsz', 28)],
        height: 1.2,
        letterSpacing: -0.4,
        color: ink,
      );

  TextStyle get _style => styleFor(widget.full ? 34 : 24, widget.ink);

  double get _gap => widget.full ? 36 : 25;
  double get _intervalHeight => widget.full ? 34 : 24;

  /// right padding carries the room the line swells into
  double get _right => _side + _swell * widget.width;
  double get _textWidth => widget.width - _side - _right;

  /// list speed, carried into the next centring spring
  double _velocity = 0;
  double _lastPixels = 0;
  DateTime _lastAt = DateTime.now();

  void _track() {
    if (!_scroll.hasClients) return;
    final now = DateTime.now();
    final dt = now.difference(_lastAt).inMicroseconds / 1e6;
    final px = _scroll.position.pixels;
    _velocity = dt > 0 && dt < 0.1 ? (px - _lastPixels) / dt : 0;
    _lastPixels = px;
    _lastAt = now;
  }

  @override
  void initState() {
    super.initState();
    _measure();
    _active = _indexAt(cowMusic.position);
    _scroll = ScrollController(initialScrollOffset: _targetFor(_active));
    _lastPixels = _scroll.initialScrollOffset;
    _scroll.addListener(_track);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void didUpdateWidget(_LyricList old) {
    super.didUpdateWidget(old);
    if (old.track.title != widget.track.title ||
        old.track.lyrics.length != widget.track.lyrics.length ||
        old.width != widget.width ||
        old.full != widget.full) {
      _measure();
      _active = -1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tick(jump: true));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  int _indexAt(Duration position) {
    final lines = _rows;
    int i = -1;
    for (var k = 0; k < lines.length; k++) {
      if (lines[k].at <= position) {
        i = k;
      } else {
        break;
      }
    }
    return i;
  }

  void _tick({bool jump = false, bool force = false}) {
    if (!mounted) return;
    final i = _indexAt(cowMusic.position);
    if (i == _active && !jump && !force) return;
    if (i != _active) setState(() => _active = i);
    _scrollTo(i, jump: jump);
  }

  /// the line's centre on the box's centre
  double _targetFor(int i) {
    if (i < 0 || i >= _tops.length) return 0;
    return _tops[i] + _heights[i] / 2;
  }

  void _scrollTo(int i, {required bool jump}) {
    if (!_scroll.hasClients || _tops.isEmpty) return;
    final until = _handsOffUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    final position = _scroll.position;
    final target = _targetFor(i).clamp(0.0, position.maxScrollExtent);
    if (jump || Motion.reduce(context)) {
      position.jumpTo(target);
      return;
    }
    // spring from where the list is, at its current speed
    final pos = position as ScrollPositionWithSingleContext;
    pos.beginActivity(BallisticScrollActivity(
      pos,
      SpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 110, ratio: 1),
        pos.pixels,
        target,
        _velocity,
      ),
      pos.context.vsync,
      true,
    ));
  }

  void _measure() {
    _rows = lyricRows(widget.track.lyrics, widget.track.duration);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    final tops = <double>[];
    final heights = <double>[];
    double y = 0;
    for (final l in _rows) {
      double h;
      if (l.interval) {
        h = _intervalHeight;
      } else {
        painter.text = TextSpan(text: l.line, style: _style);
        painter.layout(maxWidth: _textWidth);
        h = painter.height;
      }
      tops.add(y);
      heights.add(h);
      y += h + _gap;
    }
    painter.dispose();
    _tops = tops;
    _heights = heights;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = Motion.reduce(context);
    final lines = _rows;
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) {
          _handsOffUntil = DateTime.now().add(const Duration(seconds: 4));
        }
        return false;
      },
      child: AnimatedBuilder(
        animation: widget.soft,
        builder: (context, _) => ListView.builder(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          // half a box above and below, the current line is centred
          padding: EdgeInsets.fromLTRB(_side, widget.height * 0.5, _right, widget.height * 0.5),
          itemCount: lines.length,
          itemBuilder: (context, i) => _line(context, i, reduce, widget.soft.value),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, int i, bool reduce, double soft) {
    final line = _rows[i];
    final distance = (i - _active).abs();
    final active = i == _active;
    final interval = line.interval;
    final height = i < _heights.length ? _heights[i] : _intervalHeight;
    // dots sized to the type
    final dot = widget.full ? 11.0 : 8.0;

    // neighbours stay sharp, the rest gets a flat blur
    final blurTarget = distance < 2 ? 0.0 : 2.0;

    // focus 0..1 into the current line
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: active ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 650),
      // overshoots and settles
      curve: Motion.spring,
      builder: (context, rawFocus, _) {
        final focus = rawFocus.clamp(0.0, 1.0);
        // 40% at rest, 92% current
        final alpha = 0.40 + 0.52 * focus;
        final colour = widget.ink.withOpacity(alpha);
        Widget body;
        if (interval) {
          // current break fills its dots, others are three quiet ones
          body = active
              ? IntervalDots(color: widget.ink, start: line.at, end: line.end, size: dot)
              : SizedBox(
                  height: dot * 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      3,
                      (_) => Padding(
                        padding: EdgeInsets.symmetric(horizontal: dot * 0.35),
                        child: Container(
                          width: dot * 0.8,
                          height: dot * 0.8,
                          decoration: BoxDecoration(color: colour.withOpacity(alpha * 0.55), shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                );
        } else {
          // no scaler, the measured heights must stay exact
          body = Text(line.line, style: _style.copyWith(color: colour), textScaler: TextScaler.noScaling);
        }
        // transform, not font size; the measured heights must stay exact
        final moving = rawFocus > 0 && rawFocus < 1;
        Widget w = SizedBox(
          height: height,
          width: double.infinity,
          child: Transform.scale(
            scale: 1 + _swell * rawFocus,
            alignment: Alignment.centerLeft,
            filterQuality: moving ? FilterQuality.medium : null,
            child: Align(alignment: Alignment.topLeft, child: body),
          ),
        );
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: blurTarget),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOut,
          child: w,
          builder: (context, blur, child) {
            final sigma = blur * soft;
            Widget row = child!;
            if (sigma > 0.2 && !reduce) {
              row = ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
                child: row,
              );
            }
            return Padding(
              padding: EdgeInsets.only(bottom: _gap),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _handsOffUntil = null;
                  cowMusic.seek(line.at);
                  _tick(force: true);
                },
                child: row,
              ),
            );
          },
        );
      },
    );
  }
}
