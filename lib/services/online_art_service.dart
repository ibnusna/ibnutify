import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// UI1: Service untuk mengambil foto artist/album dari internet (iTunes Search API)
/// dan men-cache-nya di documents directory untuk akses offline.
///
/// Cache strategy:
/// - Key: MD5-like hash dari artist atau "album|artist" string
/// - Storage: getApplicationDocumentsDirectory()/ibnutify_art_cache/
/// - Tidak ada expiry — persistent offline
class OnlineArtService {
  OnlineArtService._();
  static final OnlineArtService instance = OnlineArtService._();

  // In-memory cache: key → local file path
  final Map<String, String> _pathCache = {};

  // Prevent concurrent fetches for the same key
  final Map<String, Future<String?>> _pendingFetches = {};

  static const String _cacheDir = 'ibnutify_art_cache';
  static const String _itunesBase =
      'https://itunes.apple.com/search';

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Ambil path gambar lokal untuk artist.
  /// Return null jika tidak ada koneksi / tidak ditemukan.
  Future<String?> getArtistImagePath(String artist) async {
    if (artist.isEmpty || artist == 'Unknown Artist') return null;
    final key = 'artist_${_sanitize(artist)}';
    return _getOrFetch(key, () => _fetchArtistUrl(artist));
  }

  /// Ambil path gambar lokal untuk album.
  /// Return null jika tidak ada koneksi / tidak ditemukan.
  Future<String?> getAlbumCoverPath(String album, String artist) async {
    if (album.isEmpty || album == 'Unknown Album') return null;
    final key = 'album_${_sanitize(album)}_${_sanitize(artist)}';
    return _getOrFetch(key, () => _fetchAlbumUrl(album, artist));
  }

  // ─── Private helpers ─────────────────────────────────────────────────────────

  Future<String?> _getOrFetch(
      String key, Future<String?> Function() fetcher) async {
    // 1. In-memory cache
    if (_pathCache.containsKey(key)) return _pathCache[key];

    // 2. Disk cache
    final cached = await _getCachedPath(key);
    if (cached != null) {
      _pathCache[key] = cached;
      return cached;
    }

    // 3. Prevent duplicate concurrent fetches
    if (_pendingFetches.containsKey(key)) {
      return _pendingFetches[key];
    }

    // 4. Fetch from network
    final future = _fetchAndCache(key, fetcher);
    _pendingFetches[key] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _pendingFetches.remove(key);
    }
  }

  Future<String?> _fetchAndCache(
      String key, Future<String?> Function() urlFetcher) async {
    try {
      final url = await urlFetcher();
      if (url == null) return null;

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;

      final dir = await _cacheDirectory();
      final file = File('${dir.path}/$key.jpg');
      await file.writeAsBytes(response.bodyBytes, flush: true);

      _pathCache[key] = file.path;
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Fetch URL foto artist dari iTunes Search API.
  Future<String?> _fetchArtistUrl(String artist) async {
    try {
      final uri = Uri.parse(_itunesBase).replace(queryParameters: {
        'term': artist,
        'media': 'music',
        'entity': 'musicArtist',
        'limit': '1',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      // iTunes returns artistLinkUrl, not image — fallback ke album search
      return _fetchArtistViaAlbumSearch(artist);
    } catch (_) {
      return null;
    }
  }

  /// Fetch URL foto artis dari album artwork (lebih reliable di iTunes).
  Future<String?> _fetchArtistViaAlbumSearch(String artist) async {
    try {
      final uri = Uri.parse(_itunesBase).replace(queryParameters: {
        'term': artist,
        'media': 'music',
        'entity': 'album',
        'limit': '3',
        'sort': 'popular',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      // Ambil artworkUrl100 dari hasil pertama dan upgrade ke 600px
      final rawUrl = results.first['artworkUrl100'] as String?;
      return rawUrl?.replaceAll('100x100bb', '600x600bb');
    } catch (_) {
      return null;
    }
  }

  /// Fetch URL cover album dari iTunes Search API.
  Future<String?> _fetchAlbumUrl(String album, String artist) async {
    try {
      final query = artist.isNotEmpty ? '$album $artist' : album;
      final uri = Uri.parse(_itunesBase).replace(queryParameters: {
        'term': query,
        'media': 'music',
        'entity': 'album',
        'limit': '5',
        'sort': 'popular',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;

      // Cari album yang paling cocok dengan nama album lokal
      final lowerAlbum = album.toLowerCase();
      Map<String, dynamic>? best;
      for (final r in results) {
        final collectionName =
            (r['collectionName'] as String?)?.toLowerCase() ?? '';
        if (collectionName.contains(lowerAlbum) ||
            lowerAlbum.contains(collectionName)) {
          best = r as Map<String, dynamic>;
          break;
        }
      }
      best ??= results.first as Map<String, dynamic>;

      final rawUrl = best['artworkUrl100'] as String?;
      return rawUrl?.replaceAll('100x100bb', '600x600bb');
    } catch (_) {
      return null;
    }
  }

  /// Cek apakah sudah ada cache di disk untuk key ini.
  Future<String?> _getCachedPath(String key) async {
    try {
      final dir = await _cacheDirectory();
      final file = File('${dir.path}/$key.jpg');
      if (await file.exists()) return file.path;
    } catch (_) {}
    return null;
  }

  /// Dapatkan direktori cache (buat jika belum ada).
  Future<Directory> _cacheDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_cacheDir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Sanitize string untuk dipakai sebagai nama file (hapus karakter tidak valid).
  String _sanitize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .substring(0, input.length > 60 ? 60 : input.length);
  }
}
