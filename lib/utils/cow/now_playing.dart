import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bluebubbles/services/backend/java_dart_interop/method_channel_service.dart';
import 'package:flutter/foundation.dart';

import 'album_palette.dart';
import 'lyrics.dart';

/// now playing
@immutable
class NowPlaying {
  final String title;
  final String artist;
  final String album;
  final AlbumPalette palette;

  /// full-res art, for the chip
  final ui.Image? art;

  /// tiny copy, upscaled for the background blur
  final ui.Image? blurSource;

  final List<LyricLine> lyrics;
  final Duration duration;

  const NowPlaying({
    required this.title,
    required this.artist,
    required this.album,
    required this.palette,
    required this.lyrics,
    required this.duration,
    this.art,
    this.blurSource,
  });

  String get subtitle => album.isEmpty ? artist : '$artist — $album';
}

/// holds the current track for the UI
class CowMusic extends ChangeNotifier {
  CowMusic() {
    // the listener published at boot; a cold engine missed it
    Future<void>.delayed(const Duration(seconds: 2), refresh);
  }

  NowPlaying? _current;
  NowPlaying? get current => _current;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  final _lyrics = LyricsService();
  Timer? _ticker;

  /// line alone; whole-service rebuilds churn the composer
  final ValueNotifier<String?> lyricLine = ValueNotifier<String?>(null);

  /// between lines
  final ValueNotifier<bool> lyricInterval = ValueNotifier<bool>(false);

  void _refreshLyricLine() {
    final next = currentLyric;
    if (lyricLine.value != next) lyricLine.value = next;
    final interval = hasLyrics && next == null;
    if (lyricInterval.value != interval) lyricInterval.value = interval;
  }

  /// last reported position; interpolate, it survives a seek
  Duration _reportedPosition = Duration.zero;
  DateTime _reportedAt = DateTime.now();

  Duration get position => _isPlaying
      ? _reportedPosition + DateTime.now().difference(_reportedAt)
      : _reportedPosition;

  /// from the MediaColors handler
  Future<void> update(Map<dynamic, dynamic> args) async {
    final title = args['title'] as String? ?? '';
    if (title.isEmpty) return;

    final artist = args['artist'] as String? ?? '';
    final album = args['album'] as String? ?? '';
    final durationMs = (args['duration'] as num?)?.toInt() ?? 0;

    _reportedPosition =
        Duration(milliseconds: (args['position'] as num?)?.toInt() ?? 0);
    _reportedAt = DateTime.now();
    _isPlaying = args['isPlaying'] as bool? ?? true;

    final sameTrack = _current?.title == title && _current?.artist == artist;
    final bytes = args['albumArt'] as Uint8List?;

    // position-only update, keep the artwork
    if (sameTrack && bytes == null) {
      notifyListeners();
      return;
    }

    if (bytes == null) {
      // different track, no artwork; bailing would leave the old one up
      final prev = _current;
      _current = NowPlaying(
        title: title,
        artist: artist,
        album: album,
        palette: prev?.palette ??
            AlbumPalette.fromPixels(Uint8List.fromList(const [])),
        lyrics: const [],
        duration: Duration(milliseconds: durationMs),
        art: prev?.art,
        blurSource: prev?.blurSource,
      );
      lyricLine.value = null;
      lyricInterval.value = false;
      _ticker?.cancel();
      notifyListeners();
      unawaited(_loadLyrics(title, artist, album,
          durationMs > 0 ? Duration(milliseconds: durationMs) : null));
      return;
    }

    // raw rgba, no codec on this path
    final w = (args['artWidth'] as num?)?.toInt() ?? 0;
    final h = (args['artHeight'] as num?)?.toInt() ?? 0;
    if (w <= 0 || h <= 0 || bytes.length < w * h * 4) return;

    final palette = AlbumPalette.fromPixels(bytes);
    final art = await _imageFromPixels(bytes, w, h);
    if (art == null) return;

    // 28px source; a bigger one shows texel blocks when stretched
    final tinyBytes = _boxDownsample(bytes, w, h, 28);
    final tiny = await _imageFromPixels(tinyBytes, 28, 28) ?? art;

    _current = NowPlaying(
      title: title,
      artist: artist,
      album: album,
      palette: palette,
      lyrics: const [],
      duration: Duration(milliseconds: durationMs),
      art: art,
      blurSource: tiny,
    );
    lyricLine.value = null;
    notifyListeners();


    // lyrics after the theme, don't wait on the network
    unawaited(_loadLyrics(title, artist, album,
        durationMs > 0 ? Duration(milliseconds: durationMs) : null));
  }

  /// transport; optimistic, the state callback corrects
  Future<void> playPause() async {
    _isPlaying = !_isPlaying;
    notifyListeners();
    await _control('playPause');
  }

  Future<void> next() => _control('next');
  Future<void> previous() => _control('previous');

  /// ask the platform what is playing
  Future<void> refresh() => _control('republish');

  /// seek; position taken as reported at once
  Future<void> seek(Duration to) async {
    _reportedPosition = to;
    _reportedAt = DateTime.now();
    notifyListeners();
    await _control('seek', {'position': to.inMilliseconds});
  }

  Future<void> _control(String action, [Map<String, Object?> args = const {}]) async {
    try {
      await mcs.invokeMethod('media-control', {'action': action, ...args});
    } catch (_) {
      // no session
    }
  }

  /// stopped
  void stopped() {
    _isPlaying = false;
    _current = null;
    _ticker?.cancel();
    lyricLine.value = null;
    lyricInterval.value = false;
    notifyListeners();
  }

  /// box-downsample rgba to n x n
  static Uint8List _boxDownsample(Uint8List src, int w, int h, int n) {
    final out = Uint8List(n * n * 4);
    final bw = w / n, bh = h / n;
    for (var oy = 0; oy < n; oy++) {
      final y0 = (oy * bh).floor(), y1 = ((oy + 1) * bh).ceil().clamp(0, h);
      for (var ox = 0; ox < n; ox++) {
        final x0 = (ox * bw).floor(), x1 = ((ox + 1) * bw).ceil().clamp(0, w);
        var r = 0, g = 0, b = 0, c = 0;
        for (var y = y0; y < y1; y++) {
          var i = (y * w + x0) * 4;
          for (var x = x0; x < x1; x++, i += 4) {
            r += src[i]; g += src[i + 1]; b += src[i + 2]; c++;
          }
        }
        final o = (oy * n + ox) * 4;
        out[o] = r ~/ c; out[o + 1] = g ~/ c; out[o + 2] = b ~/ c; out[o + 3] = 255;
      }
    }
    return out;
  }

  /// raw rgba to ui.Image, no codec
  Future<ui.Image?> _imageFromPixels(Uint8List bytes, int w, int h) {
    final done = Completer<ui.Image?>();
    try {
      ui.decodeImageFromPixels(
        bytes,
        w,
        h,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
    } catch (_) {
      return Future.value(null);
    }
    return done.future;
  }

  Future<void> _loadLyrics(
    String title,
    String artist,
    String album,
    Duration? duration,
  ) async {
    final lines = await _lyrics.fetch(
        title: title, artist: artist, album: album, duration: duration);
    final track = _current;
    // track may have changed in flight
    if (lines.isEmpty || track == null || track.title != title) return;

    _current = NowPlaying(
      title: track.title,
      artist: track.artist,
      album: track.album,
      palette: track.palette,
      lyrics: lines,
      duration: track.duration,
      art: track.art,
      blurSource: track.blurSource,
    );
    // tick; position reports are sparse
    _ticker?.cancel();
    _ticker = Timer.periodic(
        const Duration(milliseconds: 400), (_) => _refreshLyricLine());
    _refreshLyricLine();
    notifyListeners();
  }

  /// song has a synced sheet
  bool get hasLyrics => _current?.lyrics.isNotEmpty ?? false;

  /// instrumental stretch
  bool get inLyricInterval => hasLyrics && currentLyric == null;

  /// current line; null before the first and on instrumentals
  String? get currentLyric {
    final row = currentRow;
    if (row == null || row.interval) return null;
    return row.line;
  }

  List<LyricLine>? _rowsSource;
  List<LyricRow> _rows = const [];

  /// sheet as rows, built once per sheet
  List<LyricRow> get rows {
    final lyrics = _current?.lyrics;
    if (lyrics == null) return const [];
    if (!identical(lyrics, _rowsSource)) {
      _rowsSource = lyrics;
      _rows = lyricRows(lyrics, _current!.duration);
    }
    return _rows;
  }

  /// row for the current position
  LyricRow? get currentRow {
    final r = rows;
    if (r.isEmpty) return null;
    final now = position;
    LyricRow? row;
    for (final l in r) {
      if (l.at <= now) {
        row = l;
      } else {
        break;
      }
    }
    return row;
  }

  /// current instrumental span, or null
  ({Duration start, Duration end})? get currentInterval {
    if (!hasLyrics) return null;
    final row = currentRow;
    if (row == null) {
      final r = rows;
      return (start: Duration.zero, end: r.first.at);
    }
    return row.interval ? (start: row.at, end: row.end) : null;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lyrics.dispose();
    lyricLine.dispose();
    lyricInterval.dispose();
    super.dispose();
  }
}

final cowMusic = CowMusic();
