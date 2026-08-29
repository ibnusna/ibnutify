import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:ibnutify/data/models/song_model.dart';

class SmartShuffleArgs {
  final List<SongModel> queue;
  final List<int> recentSongIds;
  final int? currentSongId;
  
  SmartShuffleArgs(this.queue, this.recentSongIds, this.currentSongId);
}

class SmartShuffleService {
  /// Computes the optimized shuffle indices in a background isolate.
  static Future<List<int>> computeSmartShuffleIndices(
      List<SongModel> queue, List<int> recentSongIds, int? currentSongId) async {
    return await compute(_smartShuffleTask, SmartShuffleArgs(queue, recentSongIds, currentSongId));
  }

  static List<int> _smartShuffleTask(SmartShuffleArgs args) {
    final queue = args.queue;
    if (queue.isEmpty) return [];
    if (queue.length == 1) return [0];
    
    const int numCandidates = 8;
    final candidates = <List<int>>[];
    final random = Random();

    // Hitung frekuensi artis dari 24h recent history untuk personalisasi
    final artistFrequency = <String, int>{};
    for (final songId in args.recentSongIds) {
      final found = queue.where((s) => s.id == songId).firstOrNull;
      if (found != null) {
        final artist = found.artist.toLowerCase();
        artistFrequency[artist] = (artistFrequency[artist] ?? 0) + 1;
      }
    }

    // 1. Generate Candidates
    for (int c = 0; c < numCandidates; c++) {
      final candidate = List.generate(queue.length, (i) => i);
      candidate.shuffle(random);
      
      // Pastikan currentSong selalu di indeks 0 jika ada
      if (args.currentSongId != null) {
        final curIdx = queue.indexWhere((s) => s.id == args.currentSongId);
        if (curIdx != -1) {
          candidate.remove(curIdx);
          candidate.insert(0, curIdx);
        }
      }
      candidates.add(candidate);
    }

    // 2. Score Candidates
    final scores = List.filled(numCandidates, 0.0);
    
    for (int c = 0; c < numCandidates; c++) {
      final candidate = candidates[c];
      double score = 0.0;
      
      // Freshness Filter: kurangi skor jika lagu yang baru diputar muncul di 15 posisi teratas
      final checkLength = min(15, candidate.length);
      for (int i = 1; i < checkLength; i++) {
        final song = queue[candidate[i]];
        if (args.recentSongIds.contains(song.id)) {
          score -= (25.0 / i);
        }
      }

      // Engagement & Preference Filter
      for (int i = 1; i < candidate.length; i++) {
        final song = queue[candidate[i]];
        final skips = song.skipCount;
        final completions = song.completionCount;
        final totalInteractions = skips + completions;
        final artistKey = song.artist.toLowerCase();
        
        // Reward untuk artis favorit berdasarkan listening history
        if (artistFrequency.containsKey(artistKey)) {
          final favBonus = (artistFrequency[artistKey]! * 3.0);
          score += favBonus * ((candidate.length - i) / candidate.length);
        }

        if (totalInteractions > 0) {
          final skipRate = skips / totalInteractions;
          if (skipRate > 0.4) {
             score -= (skipRate * 18.0) * ((candidate.length - i) / candidate.length);
          }
          final completionRate = completions / totalInteractions;
          if (completionRate > 0.7) {
             score += (completionRate * 12.0) * ((candidate.length - i) / candidate.length);
          }
        }
      }
      scores[c] = score;
    }

    // 3. Pick Best Candidate
    int bestIndex = 0;
    double bestScore = scores[0];
    for (int c = 1; c < numCandidates; c++) {
      if (scores[c] > bestScore) {
        bestScore = scores[c];
        bestIndex = c;
      }
    }

    final bestSequence = List<int>.from(candidates[bestIndex]);

    // 4. Dithering (Artist Spreading)
    for (int i = 1; i < bestSequence.length; i++) {
      final currentArtist = queue[bestSequence[i]].artist;
      
      bool conflict = false;
      for (int j = 1; j <= 2; j++) {
        if (i - j >= 0) {
           if (queue[bestSequence[i - j]].artist == currentArtist) {
             conflict = true;
             break;
           }
        }
      }

      if (conflict) {
        final searchLimit = min(i + 20, bestSequence.length);
        for (int k = i + 1; k < searchLimit; k++) {
          final candidateArtist = queue[bestSequence[k]].artist;
          if (candidateArtist != currentArtist) {
            bool swapConflict = false;
            for (int j = 1; j <= 2; j++) {
              if (i - j >= 0 && queue[bestSequence[i - j]].artist == candidateArtist) {
                swapConflict = true;
                break;
              }
            }
            if (!swapConflict) {
              final temp = bestSequence[i];
              bestSequence[i] = bestSequence[k];
              bestSequence[k] = temp;
              break;
            }
          }
        }
      }
    }

    return bestSequence;
  }
}
