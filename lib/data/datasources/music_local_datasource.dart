import 'dart:io';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/data/models/playlist_model.dart';
import 'package:ibnutify/data/datasources/database_helper.dart';
import 'package:ibnutify/services/metadata_service.dart';

/// Datasource: wraps on_audio_query for native Android music scanning
/// and SQLite (sqflite) for local persistence (scores, likes, playlists, play logs).
class MusicLocalDatasource {
  final oaq.OnAudioQuery _audioQuery = oaq.OnAudioQuery();
  static const _channel = MethodChannel('com.ibnutify.ml/audio');

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  // ─── SCHEDULED RESETS (Weekly & 2-Week Cycle) ─────────────────────────────

  /// Checks and executes weekly Monday Daily Mix reset and bi-weekly On Repeat score reset.
  Future<void> checkAndPerformScheduledResets() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    // 1. On Repeat Reset (every 2 weeks / 14 days)
    const onRepeatKey = 'last_on_repeat_reset_ms';
    final lastOnRepeatMs = prefs.getInt(onRepeatKey) ?? 0;
    const fourteenDaysMs = 14 * 24 * 60 * 60 * 1000;
    if (now.millisecondsSinceEpoch - lastOnRepeatMs >= fourteenDaysMs) {
      final db = await _db;
      await db.update('songs', {'score': 0});
      await prefs.setInt(onRepeatKey, now.millisecondsSinceEpoch);
    }

    // 2. Daily Mix Reset (weekly starting every Monday)
    const dailyMixKey = 'last_daily_mix_reset_monday';
    final mondayOffset = now.weekday - DateTime.monday;
    final mondayDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: mondayOffset));
    final currentMondayStr = '${mondayDate.year}-${mondayDate.month.toString().padLeft(2, '0')}-${mondayDate.day.toString().padLeft(2, '0')}';
    final lastMondayStr = prefs.getString(dailyMixKey);

    if (lastMondayStr != currentMondayStr) {
      const seedKey = 'daily_mix_seed';
      final currentSeed = prefs.getInt(seedKey) ?? 0;
      await prefs.setInt(seedKey, currentSeed + 1);
      await prefs.setString(dailyMixKey, currentMondayStr);
    }
  }

  // ─── SCANNING ─────────────────────────────────────────────────────────────

  /// Scan all audio files from device storage and persist to SQLite.
  Future<List<SongModel>> scanDeviceSongs() async {
    // 1. Cek & Request Permission sebelum query untuk mencegah crash 'Reply already submitted'
    final hasPermission = await _audioQuery.permissionsStatus();
    if (!hasPermission) {
      final granted = await _audioQuery.permissionsRequest();
      if (!granted) {
        // Jika tetap ditolak, return empty list daripada membiarkan plugin crash
        return [];
      }
    }

    final deviceSongs = await _audioQuery.querySongs(
      sortType: oaq.SongSortType.TITLE,
      orderType: oaq.OrderType.ASC_OR_SMALLER,
      uriType: oaq.UriType.EXTERNAL,
      ignoreCase: true,
    );

    final db = await _db;
    final deletedRows = await db.query('deleted_songs');
    final deletedIds = deletedRows.map((r) => r['id'] as int).toSet();

    final List<SongModel> result = [];

    // Gunakan batch untuk performa insert/update massal
    final batch = db.batch();

    for (final song in deviceSongs) {
      if (deletedIds.contains(song.id)) continue;
      final uri = song.data ?? song.uri ?? '';
      if (uri.isEmpty) continue;

      final existingList = await db.query('songs', where: 'id = ?', whereArgs: [song.id]);

      if (existingList.isNotEmpty) {
        // Already known — preserve play stats, update metadata
        final cached = SongModel.fromMap(existingList.first);
        
        // Extract YouTube URL if not cached or missing
        String? ytUrl = cached.youtubeUrl;
        if (ytUrl == null || ytUrl.isEmpty) {
          ytUrl = await MetadataService.instance.extractYoutubeUrl(uri);
        }

        final updated = cached.copyWith(
          title: song.title,
          artist: song.artist ?? cached.artist,
          album: song.album ?? cached.album,
          duration: song.duration ?? cached.duration,
          uri: uri,
          youtubeUrl: ytUrl,
        );
        batch.update('songs', updated.toMap(), where: 'id = ?', whereArgs: [song.id]);
        result.add(updated);
      } else {
        final newSong = SongModel(
          id: song.id,
          title: song.title,
          artist: song.artist ?? 'Unknown Artist',
          album: song.album ?? 'Unknown Album',
          duration: song.duration ?? 0,
          uri: uri,
          playCount: 0,
          addedAt: DateTime.now().millisecondsSinceEpoch,
          score: 0,
          youtubeUrl: await MetadataService.instance.extractYoutubeUrl(uri),
        );
        batch.insert('songs', newSong.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
        result.add(newSong);
      }
    }

    await batch.commit(noResult: true);
    return result;
  }

  // ─── SONGS CRUD ───────────────────────────────────────────────────────────

  Future<List<SongModel>> getAllSongs() async {
    final db = await _db;
    final deletedRows = await db.query('deleted_songs');
    final deletedIds = deletedRows.map((r) => r['id'] as int).toSet();
    final maps = await db.query('songs', orderBy: 'title ASC');
    return maps
        .map((e) => SongModel.fromMap(e))
        .where((s) => !deletedIds.contains(s.id))
        .toList();
  }

  /// Top 20 songs based on the new On Repeat logic (highest score).
  /// Score increases by 10 for full listens and decreases by 5 for quick skips.
  /// Evaluated dynamically within the last 7 days.
  Future<List<SongModel>> getTopSongs({int limit = 20}) async {
    final db = await _db;
    final sevenDaysAgo = DateTime.now().millisecondsSinceEpoch - (7 * 24 * 60 * 60 * 1000);
    
    final logs = await db.query(
      'play_logs',
      where: 'timestamp >= ?',
      whereArgs: [sevenDaysAgo],
    );
    
    final allSongs = await getAllSongs();
    final Map<int, int> songScores = {};
    
    for (final song in allSongs) {
      songScores[song.id] = 0;
    }
    
    for (final log in logs) {
      final songId = log['song_id'] as int;
      final durationPlayedSecs = log['duration_played'] as int;
      
      final song = allSongs.firstWhere(
        (s) => s.id == songId,
        orElse: () => SongModel(id: -1, title: '', artist: '', album: '', duration: 0, uri: '', addedAt: 0),
      );
      if (song.id == -1) continue;
      
      final totalDurationSecs = song.duration ~/ 1000;
      int change = 0;
      if (totalDurationSecs > 0 && (durationPlayedSecs / totalDurationSecs) >= 0.8) {
        change = 10;
      } else if (durationPlayedSecs < 30) {
        change = -5;
      }
      
      songScores[songId] = (songScores[songId] ?? 0) + change;
    }
    
    final activeSongs = allSongs.where((s) => (songScores[s.id] ?? 0) > 0).toList();
    final sortedSongs = List<SongModel>.from(activeSongs);
    sortedSongs.sort((a, b) {
      final scoreA = songScores[a.id] ?? 0;
      final scoreB = songScores[b.id] ?? 0;
      if (scoreB != scoreA) {
        return scoreB.compareTo(scoreA);
      }
      return b.playCount.compareTo(a.playCount);
    });
    
    return sortedSongs.take(limit).toList();
  }

  /// Recently played — deduplicated by songId, max [limit].
  Future<List<SongModel>> getRecentlyPlayed24h({int limit = 100}) async {
    final db = await _db;
    
    final maps = await db.rawQuery('''
      SELECT *
      FROM songs
      WHERE lastPlayedAt IS NOT NULL
      ORDER BY lastPlayedAt DESC
      LIMIT ?
    ''', [limit]);

    return maps.map((e) => SongModel.fromMap(e)).toList();
  }

  Future<List<SongModel>> getRecentlyPlayed({int limit = 6}) async {
    return getRecentlyPlayed24h(limit: limit);
  }

  /// Retrieve raw listening history from the last 24 hours.
  Future<List<int>> getListeningHistory24h() async {
    final db = await _db;
    final oneDayAgo = DateTime.now().millisecondsSinceEpoch - (24 * 60 * 60 * 1000);
    
    final logs = await db.query(
      'listening_history',
      columns: ['song_id'],
      where: 'timestamp >= ?',
      whereArgs: [oneDayAgo],
      orderBy: 'timestamp DESC',
    );
    
    return logs.map((log) => log['song_id'] as int).toList();
  }

  Future<List<SongModel>> getMostPlayed({int limit = 10}) async {
    return getTopSongs(limit: limit);
  }

  Future<List<SongModel>> getLikedSongs() async {
    final db = await _db;
    final maps = await db.query('songs', where: 'isLiked = ?', whereArgs: [1]);
    return maps.map((e) => SongModel.fromMap(e)).toList();
  }

  Future<void> incrementPlayCount(int songId) async {
    final db = await _db;
    final maps = await db.query('songs', where: 'id = ?', whereArgs: [songId]);
    if (maps.isNotEmpty) {
      final song = SongModel.fromMap(maps.first);
      final updated = song.copyWith(
        playCount: song.playCount + 1,
        lastPlayedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await db.update('songs', updated.toMap(), where: 'id = ?', whereArgs: [songId]);
    }
  }

  Future<void> toggleLike(int songId) async {
    final db = await _db;
    final maps = await db.query('songs', where: 'id = ?', whereArgs: [songId]);
    if (maps.isNotEmpty) {
      final song = SongModel.fromMap(maps.first);
      final updated = song.copyWith(isLiked: !song.isLiked);
      await db.update('songs', updated.toMap(), where: 'id = ?', whereArgs: [songId]);
    }
  }

  Future<List<SongModel>> searchSongs(String query) async {
    if (query.isEmpty) return getAllSongs();
    final db = await _db;
    final maps = await db.query(
      'songs',
      where: 'title LIKE ? OR artist LIKE ? OR album LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
    );
    final results = maps.map((e) => SongModel.fromMap(e)).toList();
    
    final q = query.toLowerCase();
    results.sort((a, b) {
      int scoreA = 0;
      int scoreB = 0;
      
      final tA = a.title.toLowerCase();
      final tB = b.title.toLowerCase();
      final artA = a.artist.toLowerCase();
      final artB = b.artist.toLowerCase();
      final albA = a.album.toLowerCase();
      final albB = b.album.toLowerCase();
      
      if (tA == q) scoreA += 100;
      if (tB == q) scoreB += 100;
      
      if (tA.startsWith(q)) scoreA += 50;
      if (tB.startsWith(q)) scoreB += 50;
      
      if (tA.contains(q)) scoreA += 30;
      if (tB.contains(q)) scoreB += 30;
      
      if (artA == q) scoreA += 40;
      if (artB == q) scoreB += 40;
      
      if (artA.contains(q)) scoreA += 20;
      if (artB.contains(q)) scoreB += 20;
      
      if (albA.contains(q)) scoreA += 10;
      if (albB.contains(q)) scoreB += 10;
      
      return scoreB.compareTo(scoreA);
    });
    
    return results;
  }

  // ─── PLAY TRACKING (SMART SCORING) ────────────────────────────────────────

  /// Mencatat riwayat log pemutaran penuh setelah lagu selesai / dilewati.
  /// Menghitung score On Repeat secara otomatis.
  Future<void> recordPlayLog(int songId, int durationPlayedSecs, int totalDurationSecs) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Masukkan ke play_logs
    await db.insert('play_logs', {
      'song_id': songId,
      'timestamp': now,
      'duration_played': durationPlayedSecs,
    });
    
    // Masukkan ke listening_history
    await db.insert('listening_history', {
      'song_id': songId,
      'timestamp': now,
      'duration_listened': durationPlayedSecs,
    });

    // Kalkulasi skor Smart On Repeat
    int scoreChange = 0;
    int addSkip = 0;
    int addCompletion = 0;
    
    // Jika lagu didengarkan ≥ 90% -> +10 points
    if (totalDurationSecs > 0 && (durationPlayedSecs / totalDurationSecs) >= 0.9) {
      scoreChange = 10;
      addCompletion = 1;
    } 
    // Jika lagu dilewati dalam waktu < 30 detik -> -5 points
    else if (durationPlayedSecs < 30) {
      scoreChange = -5;
      addSkip = 1;
    }

    if (scoreChange != 0 || addSkip > 0 || addCompletion > 0) {
      final maps = await db.query('songs', where: 'id = ?', whereArgs: [songId]);
      if (maps.isNotEmpty) {
        final song = SongModel.fromMap(maps.first);
        
        int newScore = song.score + scoreChange;
        if (newScore < 0) newScore = 0; // Prevent negative scores

        final updated = song.copyWith(
          score: newScore,
          listenThroughCount: scoreChange > 0 ? song.listenThroughCount + 1 : song.listenThroughCount,
          skipCount: song.skipCount + addSkip,
          completionCount: song.completionCount + addCompletion,
        );
        await db.update('songs', updated.toMap(), where: 'id = ?', whereArgs: [songId]);
      }
    }
  }

  // ─── DUPLICATE DETECTION ──────────────────────────────────────────────────

  Future<Map<String, List<SongModel>>> getDuplicateSongs() async {
    final songs = await getAllSongs();
    final groups = <String, List<SongModel>>{};
    for (final song in songs) {
      final key = '${song.title.toLowerCase().trim()}|${song.artist.toLowerCase().trim()}';
      groups.putIfAbsent(key, () => []).add(song);
    }
    return Map.fromEntries(
      groups.entries.where((e) => e.value.length > 1),
    );
  }

  // ─── DUPLICATE SONG ────────────────────────────────────────────────────────

  Future<SongModel> duplicateSong(SongModel song) async {
    final db = await _db;
    final newId = (DateTime.now().millisecondsSinceEpoch % 2000000000).abs();
    final copy = song.copyWith(
      id: newId,
      title: '${song.title} (Copy)',
      addedAt: DateTime.now().millisecondsSinceEpoch,
      playCount: 0,
      score: 0,
    );
    await db.insert('songs', copy.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return copy;
  }

  // ─── DELETE SONG ──────────────────────────────────────────────────────────

  Future<void> deleteSong(int songId) async {
    final db = await _db;
    await db.insert(
      'deleted_songs',
      {'id': songId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    try {
      await _channel.invokeMethod('deleteSong', {'songId': songId});
    } catch (_) {}

    await db.delete('songs', where: 'id = ?', whereArgs: [songId]);
    await db.delete('playlist_songs', where: 'song_id = ?', whereArgs: [songId]);
  }

  // ─── PLAYLISTS ────────────────────────────────────────────────────────────

  Future<List<PlaylistModel>> getAllPlaylists() async {
    final db = await _db;
    final maps = await db.query('playlists', orderBy: 'createdAt DESC');
    
    final List<PlaylistModel> playlists = [];
    for (var map in maps) {
      // Ambil song IDs untuk playlist ini
      final songMaps = await db.query('playlist_songs', columns: ['song_id'], where: 'playlist_id = ?', whereArgs: [map['id']]);
      final songIds = songMaps.map((e) => e['song_id'] as int).toList();
      playlists.add(PlaylistModel.fromMap(map, songIds: songIds));
    }
    return playlists;
  }

  Future<PlaylistModel> createPlaylist(String name, {String? description}) async {
    final db = await _db;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final playlist = PlaylistModel(
      id: id,
      name: name,
      description: description,
      songIds: [],
      isCustom: true,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await db.insert('playlists', playlist.toMap());
    return playlist;
  }

  Future<void> addSongToPlaylist(String playlistId, int songId) async {
    final db = await _db;
    try {
      await db.insert('playlist_songs', {'playlist_id': playlistId, 'song_id': songId});
    } catch (_) {
      // Ignore duplicate insert
    }
  }

  Future<void> addSongsToPlaylist(String playlistId, List<int> songIds) async {
    final db = await _db;
    final batch = db.batch();
    for (var id in songIds) {
      batch.insert('playlist_songs', {'playlist_id': playlistId, 'song_id': id}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> removeSongFromPlaylist(String playlistId, int songId) async {
    final db = await _db;
    await db.delete('playlist_songs', where: 'playlist_id = ? AND song_id = ?', whereArgs: [playlistId, songId]);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final db = await _db;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  Future<List<SongModel>> getSongsForPlaylist(PlaylistModel playlist) async {
    final db = await _db;
    if (playlist.songIds.isEmpty) return [];
    
    final placeholders = List.filled(playlist.songIds.length, '?').join(',');
    final maps = await db.query('songs', where: 'id IN ($placeholders)', whereArgs: playlist.songIds);
    return maps.map((e) => SongModel.fromMap(e)).toList();
  }

  /// Artwork bytes via on_audio_query (native thumbnail)
  Future<List<int>?> queryArtwork(int songId) async {
    try {
      final artwork = await _audioQuery.queryArtwork(
        songId,
        oaq.ArtworkType.AUDIO,
        format: oaq.ArtworkFormat.JPEG,
        size: 512,
      );
      return artwork;
    } catch (_) {
      return null;
    }
  }

  // ─── DAILY MIX / ML BATCH UPDATES ─────────────────────────────────────────
  
  Future<void> updateSongFeatures(int id, double bpm, double brightness, double percussiveness, int? releaseYear) async {
    final db = await _db;
    await db.update(
      'songs',
      {
        'bpm': bpm,
        'brightness': brightness,
        'percussiveness': percussiveness,
        'release_year': releaseYear,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ─── METADATA EDIT ────────────────────────────────────────────────────────

  /// Update editable metadata: artist, album, youtube_url.
  /// Hanya field yang diberikan (non-null) yang diubah; sisanya dipertahankan.
  Future<void> updateSongMetadata(
    int songId, {
    String? artist,
    String? album,
    String? youtubeUrl,
  }) async {
    final db = await _db;
    final maps = await db.query('songs', where: 'id = ?', whereArgs: [songId]);
    if (maps.isEmpty) return;
    final song = SongModel.fromMap(maps.first);
    final updated = song.copyWith(
      artist: artist ?? song.artist,
      album: album ?? song.album,
      youtubeUrl: youtubeUrl ?? song.youtubeUrl,
    );
    await db.update('songs', updated.toMap(), where: 'id = ?', whereArgs: [songId]);
  }

  Future<void> updateSongClustersAndEra(Map<int, int> clusters, Map<int, int> eras) async {
    final db = await _db;
    final batch = db.batch();
    
    for (final songId in clusters.keys) {
      batch.update(
        'songs',
        {
          'cluster_id': clusters[songId],
          'release_year': eras[songId],
        },
        where: 'id = ?',
        whereArgs: [songId],
      );
    }
    await batch.commit(noResult: true);
  }
}
