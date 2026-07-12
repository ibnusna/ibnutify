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
    
    const int numCandidates = 5;
    final candidates = <List<int>>[];
    final random = Random();

    // 1. Generate Multiple Candidates
    for (int c = 0; c < numCandidates; c++) {
      final candidate = List.generate(queue.length, (i) => i);
      candidate.shuffle(random);
      
      // Ensure current song is always at index 0 if provided
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
      
      // Freshness Filter: penalize if recently played songs appear in the first 15 spots
      final checkLength = min(15, candidate.length);
      for (int i = 1; i < checkLength; i++) {
        final song = queue[candidate[i]];
        if (args.recentSongIds.contains(song.id)) {
          // Heavier penalty for being closer to the top
          score -= (20.0 / i); 
        }
      }

      // Engagement Filter: reward high completion rate, penalize high skip rate
      for (int i = 1; i < candidate.length; i++) {
        final song = queue[candidate[i]];
        
        final skips = song.skipCount;
        final completions = song.completionCount;
        final totalInteractions = skips + completions;
        
        if (totalInteractions > 0) {
          final skipRate = skips / totalInteractions;
          if (skipRate > 0.5) {
             // Push frequently skipped songs to the bottom
             // E.g., if it's near the top (small i), the penalty is larger
             score -= (skipRate * 15.0) * ((candidate.length - i) / candidate.length);
          }
          final completionRate = completions / totalInteractions;
          if (completionRate > 0.8) {
             // Keep frequently completed songs closer to the top
             score += (completionRate * 8.0) * ((candidate.length - i) / candidate.length);
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
    // Prevent songs from the same artist from playing back-to-back
    for (int i = 1; i < bestSequence.length; i++) {
      final currentArtist = queue[bestSequence[i]].artist;
      
      bool conflict = false;
      // Check the previous 2 songs (distance < 3)
      for (int j = 1; j <= 2; j++) {
        if (i - j >= 0) {
           if (queue[bestSequence[i - j]].artist == currentArtist) {
             conflict = true;
             break;
           }
        }
      }

      if (conflict) {
        // Find a suitable swap candidate further down
        final searchLimit = min(i + 20, bestSequence.length);
        for (int k = i + 1; k < searchLimit; k++) {
          final candidateArtist = queue[bestSequence[k]].artist;
          if (candidateArtist != currentArtist) {
            // Check if swapping causes a conflict for the new candidate at position i
            bool swapConflict = false;
            for (int j = 1; j <= 2; j++) {
              if (i - j >= 0 && queue[bestSequence[i - j]].artist == candidateArtist) {
                swapConflict = true;
                break;
              }
            }
            if (!swapConflict) {
              // Swap the elements to resolve conflict
              final temp = bestSequence[i];
              bestSequence[i] = bestSequence[k];
              bestSequence[k] = temp;
              break; // Conflict resolved, move to next i
            }
          }
        }
      }
    }

    return bestSequence;
  }
}
