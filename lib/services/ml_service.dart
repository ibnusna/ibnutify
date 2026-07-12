import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:ibnutify/data/models/song_model.dart';
import 'package:ibnutify/data/repositories/music_repository.dart';

class MLService {
  static const _channel = MethodChannel('com.ibnutify.ml/audio');

  final MusicRepository _repository;

  MLService(this._repository);

  /// Run full pipeline:
  /// 1. Extract audio features for all songs that don't have them yet.
  /// 2. Cluster all songs that have features using K-Means.
  /// 3. Update the database.
  Future<void> processAndClusterSongs(List<SongModel> songs, {Function(String)? onProgress}) async {
    if (songs.isEmpty) return;

    onProgress?.call("Extracting audio features...");
    
    // 1. Extract features for songs that don't have them yet
    int extractCount = 0;
    for (var song in songs) {
      if (song.bpm == null || song.brightness == null || song.percussiveness == null) {
        onProgress?.call("Analyzing: ${song.title} (${extractCount + 1}/${songs.length})");
        try {
          // Send to Kotlin/Python channel
          final resultString = await _channel.invokeMethod<String>(
            'extractFeatures',
            {'filePath': song.uri},
          );
          if (resultString != null) {
            final result = jsonDecode(resultString) as Map<String, dynamic>;
            if (result.containsKey('error')) {
              print("Error extracting features for ${song.title}: ${result['error']}");
            } else {
              final bpm = (result['bpm'] as num).toDouble();
              final brightness = (result['brightness'] as num).toDouble();
              final percussiveness = (result['percussiveness'] as num).toDouble();
              final releaseYear = result['release_year'] as int?;
              
              await _repository.updateSongFeatures(song.id, bpm, brightness, percussiveness, releaseYear);
              extractCount++;
            }
          }
        } catch (e) {
          print("Method channel error: $e");
        }
      }
    }

    // Refresh song list to get newly extracted features
    final updatedSongs = await _repository.getAllSongs();

    // 2. Prepare features JSON for clustering
    final featuresList = updatedSongs
        .where((s) => s.bpm != null && s.brightness != null && s.percussiveness != null)
        .map((s) => {
              'id': s.id,
              'bpm': s.bpm,
              'brightness': s.brightness,
              'percussiveness': s.percussiveness,
            })
        .toList();

    if (featuresList.isEmpty) {
      onProgress?.call("No features extracted yet to perform clustering.");
      return;
    }

    onProgress?.call("Running K-Means Clustering offline...");
    try {
      final clusterResultString = await _channel.invokeMethod<String>(
        'clusterSongs',
        {'featuresJson': jsonEncode(featuresList)},
      );

      if (clusterResultString != null) {
        final List<dynamic> clusterResult = jsonDecode(clusterResultString);
        
        final Map<int, int> clusters = {};
        final Map<int, int> eras = {};
        
        for (var item in clusterResult) {
          final id = item['id'] as int;
          final cluster = item['cluster'] as int;
          clusters[id] = cluster;
          
          // Retrieve the song
          final song = updatedSongs.firstWhere((s) => s.id == id);
          
          // Determine release year (if null, we can extract from title/album if possible, or fallback to current year)
          int finalYear = song.releaseYear ?? 2024;
          
          // Try to extract year from title or album name if it was not in ID3 tag
          if (song.releaseYear == null) {
            final yearRegex = RegExp(r'\b(19\d\d|20\d\d)\b');
            final titleMatch = yearRegex.firstMatch(song.title);
            if (titleMatch != null) {
              finalYear = int.parse(titleMatch.group(0)!);
            } else {
              final albumMatch = yearRegex.firstMatch(song.album);
              if (albumMatch != null) {
                finalYear = int.parse(albumMatch.group(0)!);
              } else {
                try {
                  final stat = FileStat.statSync(song.uri);
                  finalYear = stat.modified.year;
                } catch (_) {
                  finalYear = 2024;
                }
              }
            }
          }
          
          eras[id] = finalYear;
        }

        onProgress?.call("Saving Daily Mix classification...");
        await _repository.updateSongClustersAndEra(clusters, eras);
        onProgress?.call("Classification complete!");
      }
    } catch (e) {
      print("Clustering method channel error: $e");
      onProgress?.call("Clustering failed: $e");
    }
  }
}
