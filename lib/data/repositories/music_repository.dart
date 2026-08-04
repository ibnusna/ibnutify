import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/data/models/playlist_model.dart';
import 'package:ibnutify/data/datasources/music_local_datasource.dart';
import 'package:ibnutify/data/datasources/gemini_datasource.dart';

/// Single repository that the presentation layer interacts with.
/// Combines local datasource (on_audio_query + SQLite) and Gemini AI.
class MusicRepository {
  final MusicLocalDatasource _local;
  final GeminiDatasource _gemini;

  MusicRepository({
    required MusicLocalDatasource local,
    required GeminiDatasource gemini,
  })  : _local = local,
        _gemini = gemini;

  // ─── Songs ────────────────────────────────────────────────────────────────

  Future<List<SongModel>> scanDeviceSongs() => _local.scanDeviceSongs();
  Future<List<SongModel>> getAllSongs() => _local.getAllSongs();
  Future<List<SongModel>> getLikedSongs() => _local.getLikedSongs();
  Future<List<SongModel>> searchSongs(String query) => _local.searchSongs(query);
  Future<void> incrementPlayCount(int songId) => _local.incrementPlayCount(songId);
  Future<void> toggleLike(int songId) => _local.toggleLike(songId);
  Future<List<int>?> queryArtwork(int songId) => _local.queryArtwork(songId);

  /// Deteksi duplikat berdasarkan title + artist (case-insensitive).
  Future<Map<String, List<SongModel>>> getDuplicateSongs() => _local.getDuplicateSongs();

  /// Hapus lagu dari storage fisik dan database.
  Future<void> deleteSong(int songId) => _local.deleteSong(songId);

  // ─── Play Tracking (Smart Scoring) ────────────────────────────────────────

  /// Mencatat riwayat log pemutaran (durasi vs total) untuk update skor K-Means & On Repeat
  Future<void> recordPlayLog(int songId, int durationPlayedSecs, int totalDurationSecs) =>
      _local.recordPlayLog(songId, durationPlayedSecs, totalDurationSecs);

  // ─── Auto-Playlists ───────────────────────────────────────────────────────

  /// Top [limit] songs by score (On Repeat logic)
  Future<List<SongModel>> getTopSongs({int limit = 20}) => _local.getTopSongs(limit: limit);

  /// Recently played, deduplicated, max [limit] songs.
  Future<List<SongModel>> getRecentlyPlayed24h({int limit = 100}) =>
      _local.getRecentlyPlayed24h(limit: limit);

  /// Get listening history (raw song IDs) from last 24h
  Future<List<int>> getListeningHistory24h() => _local.getListeningHistory24h();

  // Legacy aliases
  Future<List<SongModel>> getRecentlyPlayed({int limit = 6}) =>
      _local.getRecentlyPlayed24h(limit: limit);
  Future<List<SongModel>> getMostPlayed({int limit = 10}) => _local.getTopSongs(limit: limit);

  // ─── Playlists ────────────────────────────────────────────────────────────

  Future<List<PlaylistModel>> getAllPlaylists() => _local.getAllPlaylists();

  Future<PlaylistModel> createPlaylist(String name, {String? description}) =>
      _local.createPlaylist(name, description: description);

  Future<void> addSongToPlaylist(String playlistId, int songId) =>
      _local.addSongToPlaylist(playlistId, songId);

  Future<void> addSongsToPlaylist(String playlistId, List<int> songIds) =>
      _local.addSongsToPlaylist(playlistId, songIds);

  Future<void> removeSongFromPlaylist(String playlistId, int songId) =>
      _local.removeSongFromPlaylist(playlistId, songId);

  Future<void> deletePlaylist(String playlistId) => _local.deletePlaylist(playlistId);

  Future<List<SongModel>> getSongsForPlaylist(PlaylistModel playlist) =>
      _local.getSongsForPlaylist(playlist);

  // ─── AI & ML Updates ──────────────────────────────────────────────────────

  Future<List<AIMood>> analyzeLibraryMoods(List<SongModel> songs) =>
      _gemini.analyzeLibraryMoods(songs);

  Future<void> updateSongFeatures(int id, double bpm, double brightness, double percussiveness, int? releaseYear) =>
      _local.updateSongFeatures(id, bpm, brightness, percussiveness, releaseYear);

  /// Update metadata yang bisa diedit user: artist, album, youtube_url.
  Future<void> updateSongMetadata(
    int songId, {
    String? artist,
    String? album,
    String? youtubeUrl,
  }) =>
      _local.updateSongMetadata(songId,
          artist: artist, album: album, youtubeUrl: youtubeUrl);

  Future<void> updateSongClustersAndEra(Map<int, int> clusters, Map<int, int> eras) =>
      _local.updateSongClustersAndEra(clusters, eras);
}
