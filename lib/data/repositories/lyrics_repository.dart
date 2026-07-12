import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:ibnutify/data/datasources/database_helper.dart';
import 'package:ibnutify/data/models/lyrics_cache_model.dart';
import 'package:ibnutify/services/lyrics_service.dart';
import 'package:ibnutify/services/lyrics_api_service.dart';

/// Orchestrates the 4-step lyrics resolution pipeline:
///
/// 1. **Embedded** — Read from MP3 ID3 USLT tag (instant, offline)
/// 2. **Hive cache** — Read from local permanent database (instant, offline)
/// 3. **lrclib.net** — Fetch from API (requires internet, only once per song)
/// 4. **Persist** — Save API result to Hive so it's available offline forever
///
/// Returns [LyricsResult] with lyrics text + source label.
class LyricsRepository {
  LyricsRepository._();
  static final LyricsRepository instance = LyricsRepository._();

  // In-flight request deduplication: prevent parallel fetches for same songId
  final _inFlight = <int, Future<LyricsResult?>>{};

  /// Main entry point. Call once per song change.
  Future<LyricsResult?> resolve({
    required int songId,
    required String fileUri,
    required String title,
    required String artist,
  }) {
    // Deduplicate: if already fetching for this song, reuse the future
    if (_inFlight.containsKey(songId)) return _inFlight[songId]!;
    final future = _resolve(
      songId: songId,
      fileUri: fileUri,
      title: title,
      artist: artist,
    );
    _inFlight[songId] = future;
    future.then((_) => _inFlight.remove(songId))
        .catchError((_) => _inFlight.remove(songId));
    return future;
  }

  Future<LyricsResult?> _resolve({
    required int songId,
    required String fileUri,
    required String title,
    required String artist,
  }) async {
    // ── Step 1: Embedded MP3 lyrics ─────────────────────────────────────────
    try {
      final embedded = await LyricsService.instance.getLyrics(songId, fileUri);
      if (embedded != null && embedded.isNotEmpty) {
        final lower = embedded.toLowerCase();
        final isGarbage = lower.contains('lirik tidak ditemukan') || 
                          lower.contains('lyrics not found') ||
                          lower.contains('no lyrics') ||
                          lower == 'not found';
                          
        if (!isGarbage) {
          return LyricsResult(
            lyrics: embedded,
            source: LyricsSource.embedded,
          );
        }
      }
    } catch (_) {}

    // ── Step 2: SQLite permanent cache ─────────────────────────────────────────
    try {
      final cached = await _readFromCache(songId);
      if (cached != null) return cached;
    } catch (_) {}

    // ── Step 3: lrclib.net API ───────────────────────────────────────────────
    // We do NOT wrap this in a try-catch that swallows errors.
    // If fetchWithFallback throws, it will propagate up to LyricsNotifier 
    // so we can display the debug trace.
    final apiLyrics = await LyricsApiService.instance.fetchWithFallback(
      title: title,
      artist: artist,
    );

    if (apiLyrics != null && apiLyrics.isNotEmpty) {
      // ── Step 4: Persist to Hive ─────────────────────────────────────────
      await _saveToCache(
        songId: songId,
        title: title,
        artist: artist,
        lyrics: apiLyrics,
        source: 'lrclib',
      );

      return LyricsResult(
        lyrics: apiLyrics,
        source: LyricsSource.lrclib,
      );
    }

    return null;
  }

  // ─── SQLite helpers ─────────────────────────────────────────────────────────

  Future<bool> hasCache(int songId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final count = sqflite.Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM lyrics_cache WHERE songId = ?', [songId])
      );
      return (count ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<LyricsResult?> _readFromCache(int songId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query(
        'lyrics_cache',
        where: 'songId = ?',
        whereArgs: [songId],
      );

      if (maps.isEmpty) {
        print('DEBUG [LyricsRepo]: Cache MISS for songId $songId');
        return null;
      }
      final entry = LyricsCacheModel.fromMap(maps.first);
      if (entry.lyrics.isEmpty) {
        print('DEBUG [LyricsRepo]: Cache HIT but empty for songId $songId');
        return null;
      }

      final lower = entry.lyrics.toLowerCase();
      final isGarbage = lower.contains('lirik tidak ditemukan') || 
                        lower.contains('lyrics not found') ||
                        lower.contains('no lyrics') ||
                        lower == 'not found';
                        
      if (isGarbage) {
        print('DEBUG [LyricsRepo]: Cache HIT but garbage for songId $songId');
        return null; // Ignore garbage
      }

      print('DEBUG [LyricsRepo]: Cache HIT for songId $songId (Source: ${entry.source})');
      return LyricsResult(
        lyrics: entry.lyrics,
        source: entry.source == 'lrclib'
            ? LyricsSource.lrclibCached
            : LyricsSource.embeddedCached,
      );
    } catch (e) {
      print('DEBUG [LyricsRepo]: Cache ERROR: $e');
      return null;
    }
  }

  Future<void> _saveToCache({
    required int songId,
    required String title,
    required String artist,
    required String lyrics,
    required String source,
  }) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final entry = LyricsCacheModel(
        songId: songId,
        title: title,
        artist: artist,
        lyrics: lyrics,
        source: source,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await db.insert(
        'lyrics_cache',
        entry.toMap(),
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// Clears cached lyrics for [songId] (e.g., user wants to refresh).
  Future<void> evict(int songId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('lyrics_cache', where: 'songId = ?', whereArgs: [songId]);
    } catch (_) {}
    LyricsService.instance.evict(songId);
    _inFlight.remove(songId);
  }

  /// Simpan lirik yang diinput manual oleh user ke SQLite.
  /// Menghapus cache lama untuk song yang sama sebelum menyimpan.
  Future<void> saveManual({
    required int songId,
    required String title,
    required String artist,
    required String lyrics,
  }) async {
    // Hapus embedded cache agar tidak konflik
    LyricsService.instance.evict(songId);
    _inFlight.remove(songId);
    await _saveToCache(
      songId: songId,
      title: title,
      artist: artist,
      lyrics: lyrics,
      source: 'manual',
    );
  }
}

// ─── Result types ─────────────────────────────────────────────────────────────

enum LyricsSource { embedded, embeddedCached, lrclib, lrclibCached }

class LyricsResult {
  final String lyrics;
  final LyricsSource source;

  const LyricsResult({required this.lyrics, required this.source});

  bool get isFromApi =>
      source == LyricsSource.lrclib || source == LyricsSource.lrclibCached;

  String get sourceLabel => switch (source) {
        LyricsSource.embedded => 'Embedded',
        LyricsSource.embeddedCached => 'Embedded',
        LyricsSource.lrclib => 'lrclib.net',
        LyricsSource.lrclibCached => 'lrclib.net',
      };
}
