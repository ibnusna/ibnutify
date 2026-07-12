import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ibnutify/presentation/providers/app_providers.dart';
import 'package:ibnutify/data/repositories/lyrics_repository.dart';
import 'package:ibnutify/core/utils/lrc_parser.dart';

// ─── Lyrics State ──────────────────────────────────────────────────────────

enum LyricsStatus { idle, loading, found, notFound }

class LyricsState {
  final LyricsStatus status;
  final String? lyrics;
  final List<LrcLine>? syncedLines;
  final int? songId;
  final LyricsSource? source;
  final String? debugMessage;

  const LyricsState({
    this.status = LyricsStatus.idle,
    this.lyrics,
    this.syncedLines,
    this.songId,
    this.source,
    this.debugMessage,
  });

  bool get isLoading => status == LyricsStatus.loading;
  bool get hasLyrics => status == LyricsStatus.found && lyrics != null;
  bool get hasSyncedLyrics => syncedLines != null && syncedLines!.isNotEmpty;
  bool get isFromApi =>
      source == LyricsSource.lrclib || source == LyricsSource.lrclibCached;

  LyricsState copyWith({
    LyricsStatus? status,
    String? lyrics,
    List<LrcLine>? syncedLines,
    int? songId,
    LyricsSource? source,
    String? debugMessage,
  }) {
    return LyricsState(
      status: status ?? this.status,
      lyrics: lyrics ?? this.lyrics,
      syncedLines: syncedLines ?? this.syncedLines,
      songId: songId ?? this.songId,
      source: source ?? this.source,
      debugMessage: debugMessage ?? this.debugMessage,
    );
  }
}

// ─── Lyrics Notifier ───────────────────────────────────────────────────────

class LyricsNotifier extends Notifier<LyricsState> {
  @override
  LyricsState build() {
    // ref.listen TIDAK menyebabkan rebuild Notifier — hanya subscribe ke perubahan.
    // ref.watch di sini SALAH: setiap tick posisi player akan reset state ke idle.
    ref.listen<PlayerState>(playerProvider, (prev, next) {
      final newSong = next.currentSong;
      final oldSong = prev?.currentSong;
      // Hanya fetch jika song benar-benar berganti (bukan sekadar posisi update)
      if (newSong?.id != oldSong?.id) {
        _resolveLyrics(newSong?.id, newSong?.uri, newSong?.title, newSong?.artist);
      }
    });

    // Fetch untuk lagu yang sedang aktif saat provider pertama kali dibuat.
    // Ini menangani kasus: app dibuka, lagu sudah playing, provider baru di-init.
    final current = ref.read(playerProvider).currentSong;
    if (current != null) {
      Future.microtask(() => _resolveLyrics(
            current.id,
            current.uri,
            current.title,
            current.artist,
          ));
    }

    return const LyricsState();
  }

  Future<void> _resolveLyrics(
    int? songId,
    String? uri,
    String? title,
    String? artist,
  ) async {
    if (songId == null || uri == null) {
      state = const LyricsState(status: LyricsStatus.notFound);
      return;
    }

    // Avoid re-fetching the same song (unless status is idle = initial)
    if (state.songId == songId && state.status != LyricsStatus.idle) return;

    state = LyricsState(status: LyricsStatus.loading, songId: songId);

    try {
      // Artificial delay to ensure 'loading' state is rendered
      await Future.delayed(const Duration(milliseconds: 250));

      final result = await LyricsRepository.instance.resolve(
        songId: songId,
        fileUri: uri,
        title: title ?? '',
        artist: artist ?? '',
      );

      if (state.songId != songId) return; // Song changed while loading

      if (result != null) {
        final syncedLines = LrcParser.parse(result.lyrics);
        
        state = LyricsState(
          status: LyricsStatus.found,
          lyrics: result.lyrics,
          syncedLines: syncedLines,
          songId: songId,
          source: result.source,
        );
      } else {
        state = LyricsState(status: LyricsStatus.notFound, songId: songId);
      }
    } catch (e) {
      if (state.songId == songId) {
        state = LyricsState(
          status: LyricsStatus.notFound, 
          songId: songId,
          debugMessage: e.toString(),
        );
      }
    }
  }

  /// Force re-fetch from scratch (clears all caches for current song).
  Future<void> refresh() async {
    final song = ref.read(playerProvider).currentSong;
    if (song == null) return;
    await LyricsRepository.instance.evict(song.id);
    state = const LyricsState();
    await _resolveLyrics(song.id, song.uri, song.title, song.artist);
  }

  /// Simpan lirik yang diketik manual oleh user.
  /// Parsing: normalize line endings → trim → collapse blank lines (max 2).
  /// Setelah save, update state langsung ke [found] tanpa fetch ulang.
  Future<void> saveManualLyrics(String rawInput) async {
    final song = ref.read(playerProvider).currentSong;
    if (song == null) return;

    // ── Parse ────────────────────────────────────────────────────────────────
    String cleaned = rawInput
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\uFEFF', '')       // hapus BOM
        .replaceAll('\x00', '')         // hapus null bytes
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')  // max 2 blank lines berturut
        .trim();

    if (cleaned.length < 5) return;   // terlalu pendek, abaikan

    // ── Simpan ke SQLite ─────────────────────────────────────────────────────
    await LyricsRepository.instance.saveManual(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      lyrics: cleaned,
    );

    // ── Update state langsung ─────────────────────────────────────────────────
    state = LyricsState(
      status: LyricsStatus.found,
      lyrics: cleaned,
      songId: song.id,
      source: LyricsSource.embedded,
    );
  }
}

final lyricsProvider =
    NotifierProvider<LyricsNotifier, LyricsState>(LyricsNotifier.new);
