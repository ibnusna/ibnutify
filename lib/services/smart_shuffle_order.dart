import 'package:just_audio/just_audio.dart';

/// A custom ShuffleOrder implementation that allows dynamic injection
/// of pre-calculated smart shuffle indices without stopping playback.
class SmartShuffleOrder implements ShuffleOrder {
  List<int> _indices = [];

  SmartShuffleOrder();

  /// Overwrites the current shuffle indices.
  /// Used by PlayerNotifier to inject the smart sequence.
  void updateIndices(List<int> newIndices) {
    if (newIndices.isNotEmpty) {
      _indices = List.from(newIndices);
    }
  }

  @override
  List<int> get indices => _indices;

  @override
  void insert(int index, int count) {
    for (int i = 0; i < _indices.length; i++) {
      if (_indices[i] >= index) {
        _indices[i] += count;
      }
    }
    // Append new items at the end of the shuffled list
    for (int i = 0; i < count; i++) {
      _indices.add(index + i);
    }
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    _indices.removeWhere((i) => i >= start && i < end);
    for (int i = 0; i < _indices.length; i++) {
      if (_indices[i] >= end) {
        _indices[i] -= count;
      }
    }
  }

  @override
  void shuffle({int? initialIndex}) {
    if (_indices.isEmpty) return;
    
    // DO NOTHING.
    // The indices are completely managed by updateIndices().
    // We only ensure initialIndex is placed at the front if provided, 
    // so just_audio starts playing the right track.
    if (initialIndex != null && _indices.contains(initialIndex)) {
      _indices.remove(initialIndex);
      _indices.insert(0, initialIndex);
    }
  }

  @override
  void clear() {
    _indices.clear();
  }
}
