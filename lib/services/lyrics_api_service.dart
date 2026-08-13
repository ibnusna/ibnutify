import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client for lrclib.net API — free, no API key, returns plain + synced lyrics.
///
/// API endpoint:
///   GET https://lrclib.net/api/get?artist_name=X&track_name=Y
///
/// Response fields we care about:
///   - plainLyrics   : String? — non-timed full lyrics
///   - syncedLyrics  : String? — LRC format (time-tagged lines)
///
/// No rate-limit documentation, but we add a 10s timeout and debounce
/// requests from the caller side.
class LyricsApiService {
  LyricsApiService._();
  static final LyricsApiService instance = LyricsApiService._();

  static const String _baseUrl = 'https://lrclib.net/api/get';
  static const Duration _timeout = Duration(seconds: 10);

  /// Fetches lyrics for [title] by [artist] from lrclib.net.
  ///
  /// Returns clean plain-text lyrics, or null if:
  /// - Network unavailable
  /// - Song not found (404)
  /// - Response malformed
  /// - plainLyrics is empty
  Future<String?> fetchLyrics({
    required String title,
    required String artist,
  }) async {
    if (title.trim().isEmpty) throw Exception('Judul lagu kosong');

    final cleanTitle = _sanitize(title);
    final cleanArtist = _sanitize(artist);
    List<String> debugTrace = [];

    // Attempt 1: lrclib.net
    final lrclibUri = Uri.parse(_baseUrl).replace(queryParameters: {
      'track_name': cleanTitle,
      if (cleanArtist.isNotEmpty) 'artist_name': cleanArtist,
    });

    try {
      debugTrace.add('1. Req: $lrclibUri');
      final response = await http.get(
        lrclibUri,
        headers: {
          'User-Agent': 'IbnuTify/1.0 (ibnutify@example.com)',
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      debugTrace.add('1. Res: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> json =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        final synced = json['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) {
          return synced; // Return raw LRC string with timestamps
        }

        final plain = json['plainLyrics'] as String?;
        if (plain != null && plain.trim().isNotEmpty) {
          return _cleanApiLyrics(plain);
        }
        debugTrace.add('1. Error: No lyrics in JSON');
      } else {
        debugTrace.add('1. Error: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugTrace.add('1. Exception: $e');
    }

    // Attempt 2: api.lyrics.ovh
    if (cleanArtist.isNotEmpty) {
      final ovhUri = Uri.parse('https://api.lyrics.ovh/v1/$cleanArtist/$cleanTitle');
      try {
        debugTrace.add('2. Req: $ovhUri');
        final ovhResponse = await http.get(ovhUri).timeout(const Duration(seconds: 5));
        debugTrace.add('2. Res: ${ovhResponse.statusCode}');
        if (ovhResponse.statusCode == 200) {
          final Map<String, dynamic> ovhJson =
              jsonDecode(utf8.decode(ovhResponse.bodyBytes)) as Map<String, dynamic>;
          final lyrics = ovhJson['lyrics'] as String?;
          if (lyrics != null && lyrics.trim().isNotEmpty) {
            return _cleanApiLyrics(lyrics);
          }
        } else {
          debugTrace.add('2. Error: HTTP ${ovhResponse.statusCode}');
        }
      } catch (e) {
        debugTrace.add('2. Exception: $e');
      }
    }

    throw Exception(debugTrace.join(' | '));
  }

  /// Try with artist first, then without if nothing found.
  Future<String?> fetchWithFallback({
    required String title,
    required String artist,
  }) async {
    // Attempt 1: full metadata
    final result = await fetchLyrics(title: title, artist: artist);
    if (result != null) return result;

    // Attempt 2: title only (handles "Unknown Artist" etc.)
    if (artist.isNotEmpty &&
        artist.toLowerCase() != 'unknown artist' &&
        artist.toLowerCase() != '<unknown>') {
      return await fetchLyrics(title: title, artist: '');
    }

    return null;
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  /// Light clean of API lyrics response.
  String? _cleanApiLyrics(String raw) {
    final cleaned = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return cleaned.length >= 10 ? cleaned : null;
  }

  /// Remove characters that break URL encoding or cause noise in search.
  String _sanitize(String input) {
    return input
        .replaceAll(RegExp(r'\(feat\..*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r"[^\w\s\-'\.]+"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
