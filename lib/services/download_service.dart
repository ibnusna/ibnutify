// download_service.dart — Dart bridge ke MethodChannel untuk Music Downloader
//
// Berkomunikasi dengan MainActivity.kt via channel "com.ibnutify.ml/audio".
// Menyediakan tiga aksi:
//   - downloadTrack(spotifyUrl) → Future<DownloadResult>
//   - pollProgress()            → Future<DownloadProgress>
//   - getTrackMetadata(url)     → Future<TrackMetadata?>
//
// Tidak ada AI terlibat; semua operasi adalah sistem murni.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';


/// Status download yang bisa dipantau.
enum DownloadStatus {
  idle,
  fetchingMetadata,
  downloading,
  converting,
  tagging,
  done,
  error,
  skipped,
}

DownloadStatus _parseStatus(String? raw) {
  switch (raw) {
    case 'fetching_metadata': return DownloadStatus.fetchingMetadata;
    case 'downloading':       return DownloadStatus.downloading;
    case 'converting':        return DownloadStatus.converting;
    case 'tagging':           return DownloadStatus.tagging;
    case 'done':              return DownloadStatus.done;
    case 'error':             return DownloadStatus.error;
    case 'skipped':           return DownloadStatus.skipped;
    default:                  return DownloadStatus.idle;
  }
}

/// Progress snapshot yang dikembalikan tiap polling.
class DownloadProgress {
  final DownloadStatus status;
  final double percent;
  final int etaSeconds;
  final String speedStr;
  final String currentTitle;
  final String currentArtist;
  final String filePath;
  final String error;
  final int totalSongs;
  final int currentSongIndex;
  /// [F2-2 FIX] URL cover art dari Spotify — tampilkan di UI saat download berjalan
  final String coverUrl;

  const DownloadProgress({
    this.status = DownloadStatus.idle,
    this.percent = 0.0,
    this.etaSeconds = 0,
    this.speedStr = '',
    this.currentTitle = '',
    this.currentArtist = '',
    this.filePath = '',
    this.error = '',
    this.totalSongs = 1,
    this.currentSongIndex = 1,
    this.coverUrl = '',
  });

  factory DownloadProgress.fromJson(Map<String, dynamic> json) {
    return DownloadProgress(
      status: _parseStatus(json['status'] as String?),
      percent: (json['percent'] as num? ?? 0).toDouble(),
      etaSeconds: (json['eta_seconds'] as num? ?? 0).toInt(),
      speedStr: json['speed_str'] as String? ?? '',
      currentTitle: json['current_title'] as String? ?? '',
      currentArtist: json['current_artist'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      error: json['error'] as String? ?? '',
      totalSongs: (json['total_songs'] as num? ?? 1).toInt(),
      currentSongIndex: (json['current_song_index'] as num? ?? 1).toInt(),
      coverUrl: json['cover_url'] as String? ?? '',
    );
  }

  /// Tampilan sisa waktu yang user-friendly untuk ditampilkan di chat.
  String get etaDisplay {
    if (etaSeconds <= 0) return '';
    if (etaSeconds < 60) return '${etaSeconds}s';
    final m = etaSeconds ~/ 60;
    final s = etaSeconds % 60;
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

/// Hasil akhir setelah download selesai.
class DownloadResult {
  final bool success;
  final String status;   // done | skipped | error
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String error;

  const DownloadResult({
    required this.success,
    required this.status,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.filePath = '',
    this.error = '',
  });

  factory DownloadResult.fromJson(Map<String, dynamic> json) {
    return DownloadResult(
      success: json['success'] as bool? ?? false,
      status: json['status'] as String? ?? 'error',
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
      error: json['error'] as String? ?? '',
    );
  }

  factory DownloadResult.failure(String message) {
    return DownloadResult(success: false, status: 'error', error: message);
  }
}

/// Informasi lagu yang diunduh dari playlist Spotify.
class DownloadedTrackInfo {
  final String title;
  final String artist;
  final String album;
  final String filePath;

  const DownloadedTrackInfo({
    required this.title,
    required this.artist,
    this.album = '',
    this.filePath = '',
  });

  factory DownloadedTrackInfo.fromJson(Map<String, dynamic> json) {
    return DownloadedTrackInfo(
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      filePath: json['file_path'] as String? ?? '',
    );
  }
}

/// Hasil download playlist.
class PlaylistResult {
  final bool success;
  final String playlistName;
  final int total;
  final int successful;
  final List<String> failed;
  final String playlistFolder;
  final List<DownloadedTrackInfo> downloadedTracks;
  final String error;

  const PlaylistResult({
    required this.success,
    required this.playlistName,
    required this.total,
    required this.successful,
    required this.failed,
    required this.playlistFolder,
    this.downloadedTracks = const [],
    required this.error,
  });

  factory PlaylistResult.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['downloaded_tracks'] as List<dynamic>? ?? [];
    final tracks = rawTracks
        .whereType<Map<String, dynamic>>()
        .map((e) => DownloadedTrackInfo.fromJson(e))
        .toList();

    return PlaylistResult(
      success: json['success'] as bool? ?? false,
      playlistName: json['playlist_name'] as String? ?? '',
      total: (json['total'] as num? ?? 0).toInt(),
      successful: (json['successful'] as num? ?? 0).toInt(),
      failed: (json['failed'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      playlistFolder: json['playlist_folder'] as String? ?? '',
      downloadedTracks: tracks,
      error: json['error'] as String? ?? '',
    );
  }

  factory PlaylistResult.failure(String message) {
    return PlaylistResult(
      success: false,
      playlistName: '',
      total: 0,
      successful: 0,
      failed: const [],
      playlistFolder: '',
      downloadedTracks: const [],
      error: message,
    );
  }
}

/// Metadata cepat tanpa download.
class TrackMetadata {
  final String title;
  final String artist;
  final String album;
  final String year;
  final String coverUrl;
  final String genre;

  const TrackMetadata({
    required this.title,
    required this.artist,
    required this.album,
    this.year = '',
    this.coverUrl = '',
    this.genre = '',
  });

  factory TrackMetadata.fromJson(Map<String, dynamic> json) {
    return TrackMetadata(
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      year: json['year'] as String? ?? '',
      coverUrl: json['cover_url'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
    );
  }
}

// ─── DownloadService ─────────────────────────────────────────────────────────

class DownloadService {
  static const _channel = MethodChannel('com.ibnutify.ml/audio');
  static final DownloadService _instance = DownloadService._();
  static DownloadService get instance => _instance;

  final _progressStreamController = StreamController<DownloadProgress>.broadcast();

  /// Stream progress real-time untuk komponen UI [REQ-1.2]
  Stream<DownloadProgress> get progressStream => _progressStreamController.stream;

  DownloadService._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDownloadProgress') {
        try {
          final raw = call.arguments as String?;
          if (raw != null) {
            final json = jsonDecode(raw) as Map<String, dynamic>;
            _progressStreamController.add(DownloadProgress.fromJson(json));
          }
        } catch (_) {}
      }
    });
  }

  /// Batalkan download aktif sesegera mungkin [REQ-1.3]
  Future<bool> cancelDownload() async {
    try {
      final res = await _channel.invokeMethod<bool>('cancelDownload');
      return res ?? false;
    } catch (e) {
      debugPrint('[DownloadService] cancelDownload failed: $e');
      return false;
    }
  }

  /// Kembalikan path absolut ke folder Download/Ibnutify di storage publik.
  /// Di Android, ini adalah /storage/emulated/0/Download/Ibnutify
  Future<String> getDownloadDir() async {
    // getExternalStorageDirectory() → /storage/emulated/0/Android/data/... (app-private)
    // Kita butuh public Downloads: /storage/emulated/0/Download/Ibnutify
    // Gunakan path statis untuk Android public Downloads.
    if (Platform.isAndroid) {
      return '/storage/emulated/0/Download/Ibnutify';
    }
    // Fallback untuk testing di non-Android
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/Ibnutify';
  }

  /// Minta metadata track saja (cepat, tanpa download).
  Future<TrackMetadata?> getTrackMetadata(String spotifyUrl) async {
    try {
      final raw = await _channel.invokeMethod<String>('getTrackMetadata', {
        'spotifyUrl': spotifyUrl,
      });
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['success'] != true) return null;
      return TrackMetadata.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Mulai download track. Blocking hingga selesai — panggil dari isolate/future.
  /// Progress bisa di-polling via [pollProgress()] selama ini berjalan.
  Future<DownloadResult> downloadTrack(String spotifyUrl, {String ffmpegPath = ''}) async {
    try {
      final downloadDir = await getDownloadDir();

      // Buat folder jika belum ada (Dart side sebagai backup)
      final dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final raw = await _channel.invokeMethod<String>('downloadTrack', {
        'spotifyUrl': spotifyUrl,
        'downloadDir': downloadDir,
        'ffmpegPath': ffmpegPath,
      });

      if (raw == null) return DownloadResult.failure('Tidak ada response dari downloader.');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return DownloadResult.fromJson(json);
    } on PlatformException catch (e) {
      debugPrint('[DownloadService] PlatformException in downloadTrack:');
      debugPrint('  code: ${e.code}');
      debugPrint('  message: ${e.message}');
      debugPrint('  details: ${e.details}');
      final detail = e.details != null ? '\nDetail: ${e.details}' : '';
      return DownloadResult.failure(
          '[${e.code}] ${e.message ?? 'Platform error tidak diketahui.'}$detail');
    } catch (e) {
      debugPrint('[DownloadService] Unexpected error in downloadTrack: $e');
      return DownloadResult.failure('Error: $e');
    }
  }

  /// Poll progress terkini. Panggil secara periodik saat download sedang berjalan.
  Future<DownloadProgress> pollProgress() async {
    try {
      final raw = await _channel.invokeMethod<String>('getDownloadProgress');
      if (raw == null) return const DownloadProgress();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final progress = DownloadProgress.fromJson(json);
      _progressStreamController.add(progress);
      return progress;
    } catch (_) {
      return const DownloadProgress();
    }
  }

  /// Mengambil log debug python saat proses download.
  Future<String> getDownloadLog() async {
    try {
      final raw = await _channel.invokeMethod<String>('getDownloadLog');
      return raw ?? 'Tidak ada log.';
    } catch (e) {
      return 'Gagal mengambil log: $e';
    }
  }

  /// Download seluruh playlist dari Spotify URL.
  Future<PlaylistResult> downloadPlaylist(String spotifyUrl, {String ffmpegPath = ''}) async {
    try {
      final downloadDir = await getDownloadDir();
      final dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final raw = await _channel.invokeMethod<String>('downloadPlaylist', {
        'spotifyUrl': spotifyUrl,
        'downloadDir': downloadDir,
        'ffmpegPath': ffmpegPath,
      });

      if (raw == null) return PlaylistResult.failure('Tidak ada response dari downloader.');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PlaylistResult.fromJson(json);
    } on PlatformException catch (e) {
      return PlaylistResult.failure(e.message ?? 'Platform error tidak diketahui.');
    } catch (e) {
      return PlaylistResult.failure('Error: $e');
    }
  }

  /// Validasi apakah string adalah Spotify track URL yang valid.
  static bool isSpotifyTrackUrl(String input) {
    return input.contains('open.spotify.com/track/') ||
        input.contains('spotify:track:');
  }

  /// Validasi apakah string adalah Spotify playlist/album URL yang valid.
  static bool isSpotifyPlaylistUrl(String input) {
    return input.contains('open.spotify.com/playlist/') ||
        input.contains('spotify:playlist:') ||
        input.contains('open.spotify.com/album/') ||
        input.contains('spotify:album:');
  }

  /// Validasi apakah string adalah Spotify track atau playlist URL.
  static bool isSpotifyUrl(String input) {
    return isSpotifyTrackUrl(input) || isSpotifyPlaylistUrl(input);
  }
}
