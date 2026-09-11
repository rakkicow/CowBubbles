import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// one synced line
typedef LyricLine = ({Duration at, String line});

/// a row: lyric, or instrumental interval
typedef LyricRow = ({Duration at, Duration end, String line, bool interval});

bool isLyricMarker(String line) {
  final t = line.trim();
  return t.isEmpty || t == '\u266A' || t == '\u266B';
}

/// rows, with the implied intervals inserted
// lrc carries starts only, so line length is guessed
List<LyricRow> lyricRows(List<LyricLine> lines, Duration duration) {
  if (lines.isEmpty) return const [];
  const minIntro = Duration(seconds: 4);
  const minGap = Duration(seconds: 9);
  const lineLength = Duration(seconds: 4);
  final out = <LyricRow>[];
  Duration endOf(int i) => i + 1 < lines.length
      ? lines[i + 1].at
      : (duration > lines[i].at ? duration : lines[i].at + const Duration(seconds: 20));

  if (lines.first.at >= minIntro && !isLyricMarker(lines.first.line)) {
    out.add((at: Duration.zero, end: lines.first.at, line: '', interval: true));
  }
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final end = endOf(i);
    if (isLyricMarker(l.line)) {
      out.add((at: l.at, end: end, line: '', interval: true));
      continue;
    }
    out.add((at: l.at, end: end, line: l.line, interval: false));
    final gap = end - l.at;
    final nextMarked = i + 1 < lines.length && isLyricMarker(lines[i + 1].line);
    if (gap >= minGap && !nextMarked) {
      out.add((at: l.at + lineLength, end: end, line: '', interval: true));
    }
  }
  return out;
}

/// synced lyrics from lrclib
// no sheet is normal, not an error
class LyricsService {
  static const _host = 'lrclib.net';

  final _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 10)
    // bounded pool
    ..maxConnectionsPerHost = 4;

  /// hits, kept for the session
  final Map<String, List<LyricLine>> _cache = {};

  /// misses, expiring
  final Map<String, DateTime> _misses = {};
  static const _missTtl = Duration(minutes: 10);

  String _key(String title, String artist) =>
      '${title.toLowerCase()}|${artist.toLowerCase()}';

  Future<List<LyricLine>> fetch({
    required String title,
    required String artist,
    String album = '',
    Duration? duration,
  }) async {
    if (title.isEmpty) return const [];
    final key = _key(title, artist);
    final cached = _cache[key];
    if (cached != null) return cached;

    final missedAt = _misses[key];
    if (missedAt != null && DateTime.now().difference(missedAt) < _missTtl) {
      return const [];
    }

    final lines = await _get(title, artist, album, duration) ??
        await _search(title, artist) ??
        const <LyricLine>[];

    if (lines.isEmpty) {
      _misses[key] = DateTime.now();
    } else {
      _cache[key] = lines;
      _misses.remove(key);
    }
    return lines;
  }

  /// exact lookup, all four fields
  Future<List<LyricLine>?> _get(
    String title,
    String artist,
    String album,
    Duration? duration,
  ) async {
    final params = {
      'track_name': title,
      'artist_name': artist,
      if (album.isNotEmpty) 'album_name': album,
      if (duration != null) 'duration': '${duration.inSeconds}',
    };
    final body = await _request(Uri.https(_host, '/api/get', params));
    if (body == null) return null;
    final json = jsonDecode(body);
    if (json is! Map) return null;
    return _parseLrc(json['syncedLyrics'] as String?);
  }

  /// fuzzy search fallback
  Future<List<LyricLine>?> _search(String title, String artist) async {
    final body = await _request(Uri.https(_host, '/api/search', {
      'track_name': title,
      'artist_name': artist,
    }));
    if (body == null) return null;
    final json = jsonDecode(body);
    if (json is! List) return null;
    for (final item in json) {
      if (item is! Map) continue;
      final parsed = _parseLrc(item['syncedLyrics'] as String?);
      if (parsed != null && parsed.isNotEmpty) return parsed;
    }
    return null;
  }

  Future<String?> _request(Uri uri) async {
    HttpClientResponse? res;
    try {
      final req = await _client.getUrl(uri);
      // lrclib wants a user agent
      req.headers.set(HttpHeaders.userAgentHeader,
          'CowBubbles/0.1 (https://github.com/OpenBubbles)');
      res = await req.close().timeout(const Duration(seconds: 8));

      // read every response to completion or the pool exhausts
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return null;
      return body;
    } catch (_) {
      // drain whatever arrived; any failure means no lyrics
      try {
        await res?.drain<void>();
      } catch (_) {}
      return null;
    }
  }

  /// parse `[mm:ss.xx] words`, several stamps per line
  static List<LyricLine>? _parseLrc(String? lrc) {
    if (lrc == null || lrc.trim().isEmpty) return null;
    final stamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final out = <LyricLine>[];

    for (final raw in const LineSplitter().convert(lrc)) {
      final matches = stamp.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      for (final m in matches) {
        final minutes = int.parse(m.group(1)!);
        final seconds = int.parse(m.group(2)!);
        final fracRaw = m.group(3);
        // 2 digits = centiseconds, 3 = milliseconds
        final frac = fracRaw == null
            ? 0
            : (fracRaw.length == 2
                ? int.parse(fracRaw) * 10
                : int.parse(fracRaw.padRight(3, '0')));
        out.add((
          at: Duration(minutes: minutes, seconds: seconds, milliseconds: frac),
          line: text,
        ));
      }
    }

    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  void dispose() => _client.close(force: true);
}
