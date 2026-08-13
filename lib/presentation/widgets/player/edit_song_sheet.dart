import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/lyrics_provider.dart';
import '../common/song_artwork_widget.dart';

/// Bottom sheet Edit Lagu — 3 tab: Metadata, YouTube URL, Lirik.
/// Dipanggil dari MoreOptionsSheet via tombol "Edit Lagu".
///
/// Fixes:
/// - Sheet TUTUP otomatis setelah simpan sukses.
/// - Snackbar muncul di parent scaffold (capture sebelum pop).
/// - Lirik tab: panel NOW PLAYING real-time untuk monitoring timestamp.
class EditSongSheet extends ConsumerStatefulWidget {
  final SongModel song;

  const EditSongSheet({super.key, required this.song});

  @override
  ConsumerState<EditSongSheet> createState() => _EditSongSheetState();
}

class _EditSongSheetState extends ConsumerState<EditSongSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Tab 0 — Metadata
  late final TextEditingController _artistCtrl;
  late final TextEditingController _albumCtrl;

  // Tab 1 — YouTube URL
  late final TextEditingController _ytCtrl;

  // Tab 2 — Lirik
  late final TextEditingController _lyricsCtrl;

  bool _savingMeta = false;
  bool _savingYt = false;
  bool _savingLyrics = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _artistCtrl = TextEditingController(text: widget.song.artist);
    _albumCtrl = TextEditingController(text: widget.song.album);
    _ytCtrl = TextEditingController(text: widget.song.youtubeUrl ?? '');

    // Pre-fill lirik dari state provider jika lagu aktif
    final lyricsState = ref.read(lyricsProvider);
    final existingLyrics =
        (lyricsState.songId == widget.song.id && lyricsState.lyrics != null)
            ? lyricsState.lyrics!
            : '';
    _lyricsCtrl = TextEditingController(text: existingLyrics);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _artistCtrl.dispose();
    _albumCtrl.dispose();
    _ytCtrl.dispose();
    _lyricsCtrl.dispose();
    super.dispose();
  }

  // ─── Save Handlers ──────────────────────────────────────────────────────────
  // PENTING: Capture ScaffoldMessenger & Navigator SEBELUM await dan sebelum
  // Navigator.pop() — karena setelah pop, context tidak lagi valid untuk snackbar.

  Future<void> _saveMeta() async {
    final artist = _artistCtrl.text.trim();
    final album = _albumCtrl.text.trim();
    if (artist.isEmpty) return;

    setState(() => _savingMeta = true);

    // Capture sebelum async
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      await ref.read(songsProvider.notifier).updateMetadata(
            widget.song.id,
            artist: artist,
            album: album.isEmpty ? null : album,
          );

      // Tutup sheet DULU, lalu tampilkan snackbar di parent
      nav.pop();
      messenger.showSnackBar(_successSnack('✓ Metadata berhasil disimpan'));
    } catch (e) {
      if (mounted) setState(() => _savingMeta = false);
      messenger.showSnackBar(_errorSnack('Gagal menyimpan: $e'));
    }
  }

  Future<void> _saveYoutube() async {
    final url = _ytCtrl.text.trim();

    setState(() => _savingYt = true);

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      await ref.read(songsProvider.notifier).updateMetadata(
            widget.song.id,
            youtubeUrl: url.isEmpty ? null : url,
          );

      nav.pop();
      messenger.showSnackBar(
          _successSnack(url.isEmpty ? '✓ YouTube URL dihapus' : '✓ YouTube URL disimpan'));
    } catch (e) {
      if (mounted) setState(() => _savingYt = false);
      messenger.showSnackBar(_errorSnack('Gagal menyimpan: $e'));
    }
  }

  Future<void> _saveLyrics() async {
    final text = _lyricsCtrl.text.trim();
    if (text.length < 5) {
      ScaffoldMessenger.of(context)
          .showSnackBar(_errorSnack('Lirik terlalu pendek'));
      return;
    }

    setState(() => _savingLyrics = true);

    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      await ref.read(lyricsProvider.notifier).updateLyricsForSong(
            songId: widget.song.id,
            title: widget.song.title,
            artist: widget.song.artist,
            rawInput: text,
          );

      nav.pop();
      messenger.showSnackBar(_successSnack('✓ Lirik berhasil disimpan'));
    } catch (e) {
      if (mounted) setState(() => _savingLyrics = false);
      messenger.showSnackBar(_errorSnack('Gagal menyimpan: $e'));
    }
  }

  /// Shift timestamp — TIDAK menutup sheet agar user bisa shift berkali-kali
  /// dan memantau efeknya lewat panel NOW PLAYING real-time di bawah tombol shift.
  Future<void> _shiftTimestamps(double secs) async {
    final lyricsState = ref.read(lyricsProvider);
    if (!lyricsState.hasSyncedLyrics || lyricsState.songId != widget.song.id) {
      ScaffoldMessenger.of(context).showSnackBar(_errorSnack(
          'Aktifkan lagu ini dulu & pastikan ada lirik LRC tersinkronisasi'));
      return;
    }
    await ref.read(lyricsProvider.notifier).shiftTimestamps(secs);
    if (mounted) {
      final label = secs > 0
          ? '+${secs.toStringAsFixed(0)}s — lirik maju'
          : '${secs.toStringAsFixed(0)}s — lirik mundur';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          backgroundColor: AppColors.primary.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 900),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  // ─── Snackbar helpers ───────────────────────────────────────────────────────

  SnackBar _successSnack(String msg) => SnackBar(
        content: Text(msg,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFF1DB954),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  SnackBar _errorSnack(String msg) => SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),

              // Song header
              _SongHeader(song: widget.song),

              // Tab bar
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                  ),
                  labelColor: AppColors.primary,
                  unselectedLabelColor: AppColors.onSurfaceVariant,
                  labelStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'Metadata'),
                    Tab(text: 'YouTube'),
                    Tab(text: 'Lirik'),
                  ],
                ),
              ),

              // Tab content
              Flexible(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _MetadataTab(
                      artistCtrl: _artistCtrl,
                      albumCtrl: _albumCtrl,
                      saving: _savingMeta,
                      onSave: _saveMeta,
                    ),
                    _YoutubeTab(
                      ytCtrl: _ytCtrl,
                      saving: _savingYt,
                      onSave: _saveYoutube,
                    ),
                    _LyricsTab(
                      song: widget.song,
                      lyricsCtrl: _lyricsCtrl,
                      saving: _savingLyrics,
                      onSave: _saveLyrics,
                      onShift: _shiftTimestamps,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Song Header ──────────────────────────────────────────────────────────────

class _SongHeader extends StatelessWidget {
  final SongModel song;

  const _SongHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          SongArtworkWidget(song: song, size: 46, borderRadius: 6),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit Lagu',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  song.title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song.artist,
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Metadata ────────────────────────────────────────────────────────────

class _MetadataTab extends StatelessWidget {
  final TextEditingController artistCtrl;
  final TextEditingController albumCtrl;
  final bool saving;
  final VoidCallback onSave;

  const _MetadataTab({
    required this.artistCtrl,
    required this.albumCtrl,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('NAMA ARTIS'),
          const SizedBox(height: 6),
          _StyledTextField(
            controller: artistCtrl,
            hint: 'Nama artis...',
            icon: Icons.person_rounded,
          ),
          const SizedBox(height: 16),
          _FieldLabel('ALBUM'),
          const SizedBox(height: 6),
          _StyledTextField(
            controller: albumCtrl,
            hint: 'Nama album...',
            icon: Icons.album_rounded,
          ),
          const SizedBox(height: 24),
          _SaveButton(
            id: 'save_metadata_btn',
            label: 'Simpan Metadata',
            icon: Icons.save_rounded,
            saving: saving,
            onTap: saving ? null : onSave,
          ),
        ],
      ),
    );
  }
}

// ─── Tab: YouTube URL ─────────────────────────────────────────────────────────

class _YoutubeTab extends StatelessWidget {
  final TextEditingController ytCtrl;
  final bool saving;
  final VoidCallback onSave;

  const _YoutubeTab({
    required this.ytCtrl,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel('URL YOUTUBE MUSIC VIDEO'),
          const SizedBox(height: 6),
          _StyledTextField(
            controller: ytCtrl,
            hint: 'https://www.youtube.com/watch?v=...',
            icon: Icons.play_circle_outline_rounded,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.onSurfaceVariant.withOpacity(0.5), size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'URL ini akan digunakan saat memutar musik video. '
                  'Kosongkan untuk menghapus.',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _SaveButton(
            id: 'save_youtube_btn',
            label: 'Simpan URL',
            icon: Icons.link_rounded,
            saving: saving,
            onTap: saving ? null : onSave,
          ),
        ],
      ),
    );
  }
}

// ─── Tab: Lirik ───────────────────────────────────────────────────────────────

class _LyricsTab extends ConsumerWidget {
  final SongModel song;
  final TextEditingController lyricsCtrl;
  final bool saving;
  final VoidCallback onSave;
  final Future<void> Function(double secs) onShift;

  const _LyricsTab({
    required this.song,
    required this.lyricsCtrl,
    required this.saving,
    required this.onSave,
    required this.onShift,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricsState = ref.watch(lyricsProvider);
    final isActiveSong = lyricsState.songId == song.id;
    final hasSynced = isActiveSong && lyricsState.hasSyncedLyrics;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── NOW PLAYING real-time panel ───────────────────────────────────
          // Hanya tampil jika lagu ini sedang aktif — membantu user memonitor
          // efek shift timestamp tanpa harus menutup sheet.
          if (isActiveSong) _NowPlayingPanel(song: song),
          if (isActiveSong) const SizedBox(height: 16),

          // ── Timestamp Offset Section ──────────────────────────────────────
          _FieldLabel('PENYESUAIAN TIMESTAMP'),
          const SizedBox(height: 4),
          Text(
            hasSynced
                ? 'Tap untuk geser semua baris sekaligus. Lihat panel di atas untuk hasil real-time.'
                : isActiveSong
                    ? 'Lirik LRC belum tersedia untuk lagu ini.'
                    : 'Aktifkan lagu ini dulu agar timestamp bisa digeser.',
            style: TextStyle(
              color: AppColors.onSurfaceVariant.withOpacity(hasSynced ? 0.7 : 0.4),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Opacity(
            opacity: hasSynced ? 1.0 : 0.3,
            child: IgnorePointer(
              ignoring: !hasSynced,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _OffsetChip(label: '−5s', onTap: () => onShift(-5.0)),
                  _OffsetChip(label: '−2s', onTap: () => onShift(-2.0)),
                  _OffsetChip(label: '−1s', onTap: () => onShift(-1.0)),
                  _OffsetChip(label: '+1s', onTap: () => onShift(1.0), positive: true),
                  _OffsetChip(label: '+2s', onTap: () => onShift(2.0), positive: true),
                  _OffsetChip(label: '+5s', onTap: () => onShift(5.0), positive: true),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 20),

          // ── Lyrics Text Editor ────────────────────────────────────────────
          _FieldLabel('TEKS LIRIK'),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: TextField(
              controller: lyricsCtrl,
              maxLines: 10,
              minLines: 6,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 13,
                height: 1.6,
                fontFamily: 'monospace',
              ),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: '[00:10.500]Baris pertama lirik\n[00:14.200]Baris kedua lirik\n\n'
                    'atau tanpa timestamp:\nBaris pertama\nBaris kedua',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.18),
                  fontSize: 12,
                  height: 1.6,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.onSurfaceVariant.withOpacity(0.4), size: 12),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Format LRC [mm:ss.ms] untuk timestamp. Lirik disimpan permanen.',
                  style: TextStyle(
                    color: AppColors.onSurfaceVariant.withOpacity(0.45),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SaveButton(
            id: 'save_lyrics_btn',
            label: 'Simpan Lirik',
            icon: Icons.save_rounded,
            saving: saving,
            onTap: saving ? null : onSave,
          ),
        ],
      ),
    );
  }
}

// ─── NOW PLAYING Panel ────────────────────────────────────────────────────────
// Menampilkan baris lirik yang sedang aktif sesuai posisi playback secara real-time.
// Dipakai di tab Lirik untuk membantu user memantau efek shift timestamp.

class _NowPlayingPanel extends ConsumerWidget {
  final SongModel song;

  const _NowPlayingPanel({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(playerProvider.select((p) => p.position));
    final lyricsState = ref.watch(lyricsProvider);

    final hasSynced = lyricsState.hasSyncedLyrics &&
        lyricsState.songId == song.id;

    // Cari baris aktif berdasarkan posisi pemutaran
    String activeLine = '—';
    String nextLine = '';
    if (hasSynced) {
      final lines = lyricsState.syncedLines!;
      int activeIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (position >= lines[i].timestamp) {
          activeIndex = i;
        } else {
          break;
        }
      }
      if (activeIndex >= 0) {
        activeLine = lines[activeIndex].text.isEmpty ? '♪' : lines[activeIndex].text;
        if (activeIndex + 1 < lines.length) {
          nextLine = lines[activeIndex + 1].text;
        }
      } else if (lines.isNotEmpty) {
        activeLine = '— menunggu lirik pertama —';
      }
    }

    // Format posisi sebagai mm:ss
    final totalSecs = position.inSeconds;
    final mm = (totalSecs ~/ 60).toString().padLeft(2, '0');
    final ss = (totalSecs % 60).toString().padLeft(2, '0');
    final posLabel = '$mm:$ss';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: hasSynced ? AppColors.primary : AppColors.onSurfaceVariant,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                hasSynced ? 'NOW PLAYING  ·  $posLabel' : 'NOW PLAYING  ·  Tidak ada LRC',
                style: TextStyle(
                  color: hasSynced
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant.withOpacity(0.5),
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Baris aktif
          Text(
            hasSynced ? activeLine : '— Putar lagu & pastikan ada lirik LRC —',
            style: TextStyle(
              color: hasSynced ? Colors.white : AppColors.onSurfaceVariant.withOpacity(0.4),
              fontSize: hasSynced ? 15 : 12,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),

          // Baris berikutnya (preview)
          if (hasSynced && nextLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              nextLine,
              style: TextStyle(
                color: Colors.white.withOpacity(0.35),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.onSurfaceVariant.withOpacity(0.5),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _StyledTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;

  const _StyledTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 14,
        ),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppColors.onSurfaceVariant, size: 20),
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.onSurfaceVariant.withOpacity(0.4),
            fontSize: 13,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 0, vertical: 14),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: AppColors.primary.withOpacity(0.6), width: 1.5),
          ),
          enabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final bool saving;
  final VoidCallback? onTap;

  const _SaveButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.saving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: Key(id),
        onPressed: onTap,
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black),
              )
            : Icon(icon, size: 18),
        label: Text(saving ? 'Menyimpan...' : label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _OffsetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool positive;

  const _OffsetChip({
    required this.label,
    required this.onTap,
    this.positive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = positive ? AppColors.primary : AppColors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
