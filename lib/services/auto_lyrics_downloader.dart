import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:ibnutify/data/datasources/music_local_datasource.dart';
import 'package:ibnutify/data/repositories/lyrics_repository.dart';

/// A background service that checks all songs in the local database and downloads
/// their lyrics if they don't already have embedded or cached lyrics.
class AutoLyricsDownloader {
  AutoLyricsDownloader._();
  static final AutoLyricsDownloader instance = AutoLyricsDownloader._();

  bool _isRunning = false;
  
  /// Start the auto downloader. It will run asynchronously in the background.
  Future<void> start(MusicLocalDatasource musicDataSource) async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      debugPrint('DEBUG [AutoDownloader]: Starting background lyrics sync...');
      final songs = await musicDataSource.getAllSongs();
      debugPrint('DEBUG [AutoDownloader]: Found ${songs.length} songs to check.');

      for (final song in songs) {
        if (!_isRunning) break;

        final hasCache = await LyricsRepository.instance.hasCache(song.id);
        if (hasCache) {
          // Already have cached lyrics, skip
          continue;
        }

        // Try to resolve (this checks embedded -> cache -> API)
        debugPrint('DEBUG [AutoDownloader]: Checking lyrics for "${song.title}" - ${song.artist}');
        
        try {
          final result = await LyricsRepository.instance.resolve(
            songId: song.id,
            fileUri: song.uri,
            title: song.title,
            artist: song.artist,
          );

          if (result != null && result.source == LyricsSource.lrclib) {
            debugPrint('DEBUG [AutoDownloader]: Successfully downloaded and cached lyrics for "${song.title}"');
            // Delay to avoid hitting rate limits on lrclib.net (HTTP 429)
            await Future.delayed(const Duration(seconds: 3));
          } else {
            // Either failed, or found embedded lyrics. Still delay slightly to be safe.
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (e) {
          debugPrint('DEBUG [AutoDownloader]: Failed for "${song.title}": $e');
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      debugPrint('DEBUG [AutoDownloader]: Background sync completed.');
    } finally {
      _isRunning = false;
    }
  }

  void stop() {
    _isRunning = false;
    debugPrint('DEBUG [AutoDownloader]: Stopped background sync.');
  }
}
