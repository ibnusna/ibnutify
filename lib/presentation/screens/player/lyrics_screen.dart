import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/album_art_service.dart';
import '../../providers/app_providers.dart';
import '../../providers/album_art_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../widgets/common/song_artwork_widget.dart';

/// Full-screen Lyrics view — mirip Samsung Music / Spotify Lyrics UI.
///
/// Layout:
/// ┌──────────────────────────────┐
/// │  ↓   Song Title   ⋮         │  Header
/// │      Artist Name            │
/// ├──────────────────────────────┤
/// │                              │
/// │  Baris lirik pertama         │  ← active (bright white, bold)
/// │                              │
/// │  Baris lirik kedua           │  ← non-active (dim white)
/// │                              │
/// │  ...                         │
/// └──────────────────────────────┘
///
/// Background: dynamic dark gradient dari album art (smooth transition).
/// Swipe down untuk dismiss.
class LyricsScreen extends ConsumerStatefulWidget {
  const LyricsScreen({super.key});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradientCtrl;
  List<Color> _prevGradient = AlbumArtService.kFallbackGradient;
  List<Color> _currGradient = AlbumArtService.kFallbackGradient;

  final ScrollController _scroll = ScrollController();
  double _dragStart = 0;

  @override
  void initState() {
    super.initState();
    _gradientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final art = ref.read(albumArtProvider);
      setState(() {
        _prevGradient = _currGradient = art.gradientColors;
        _gradientCtrl.value = 1.0;
      });
    });
  }

  @override
  void dispose() {
    _gradientCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _animateGradient(List<Color> next) {
    _prevGradient = _currGradient;
    _currGradient = next;
    _gradientCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider).currentSong;
    final lyricsState = ref.watch(lyricsProvider);
    final albumArt = ref.watch(albumArtProvider);

    ref.listen<AlbumArtState>(albumArtProvider, (prev, next) {
      if (prev?.gradientColors != next.gradientColors) {
        _animateGradient(next.gradientColors);
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onVerticalDragStart: (d) => _dragStart = d.globalPosition.dy,
        onVerticalDragEnd: (d) {
          final dragDistance = (d.globalPosition.dy) - _dragStart;
          if ((d.primaryVelocity ?? 0) > 300 || dragDistance > 80) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          children: [
            // ── Animated dynamic gradient background ──────────────────────────
            AnimatedBuilder(
              animation: _gradientCtrl,
              builder: (_, __) {
                final t = Curves.easeInOut.transform(_gradientCtrl.value);
                final blended = List.generate(
                  _currGradient.length,
                  (i) => Color.lerp(
                    i < _prevGradient.length ? _prevGradient[i] : _prevGradient.last,
                    _currGradient[i],
                    t,
                  )!,
                );
                final topColor = blended.first;
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 1.0],
                      colors: [
                        topColor,
                        _darken(topColor, 0.3),
                        const Color(0xFF121212),
                      ],
                    ),
                  ),
                );
              },
            ),

            // ── Scrim overlay untuk keterbacaan teks ──────────────────────────
            // Opacity dikurangi agar warna dinamis album art tetap visible.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.1),
                      Colors.black.withOpacity(0.2),
                      Colors.transparent, // Fade out scrim at the bottom to reveal dark background
                    ],
                  ),
                ),
              ),
            ),

            // ── Main content ──────────────────────────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  _Header(song: song),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: _buildBody(lyricsState, albumArt, song),
                    ),
                  ),
                  // ── Mini Player Footer (Task 5) ────────────────────────────
                  _MiniPlayerFooter(song: song),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LyricsState lyricsState, AlbumArtState albumArt, dynamic song) {
    if (lyricsState.isLoading) {
      return const _LoadingView(key: ValueKey('loading'));
    }
    if (lyricsState.hasLyrics) {
      return _LyricsView(
        key: ValueKey('ly_${lyricsState.songId}'),
        lyricsState: lyricsState,
        scroll: _scroll,
      );
    }
    // Song dikirim via constructor — TIDAK pakai ref.watch di dalam widget
    // agar tidak ada provider dependency di AnimatedSwitcher child
    // yang bisa trigger _dependents.isEmpty assertion saat pop.
    return _ManualLyricsInputView(
      key: const ValueKey('manual_input'),
      song: song,
    );
  }

  Color _darken(Color c, double factor) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withLightness((hsl.lightness * factor).clamp(0.0, 1.0))
        .toColor();
  }
}

// ─── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final dynamic song; // SongModel?

  const _Header({this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Down chevron
          IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white,
              size: 30,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),

          // Song title + artist center
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (song != null)
                  Text(
                    song.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                if (song != null)
                  const SizedBox(height: 1),
                if (song != null)
                  Text(
                    song.artist,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  )
                else
                  const Text(
                    'LYRICS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.5,
                    ),
                  ),
              ],
            ),
          ),

          // Menu button (balancer)
          IconButton(
            icon: Icon(Icons.more_vert_rounded,
                color: Colors.white.withOpacity(0.7), size: 22),
            onPressed: null, // reserved
          ),
        ],
      ),
    );
  }
}

// ─── Loading View ─────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Memuat lirik…',
            style: TextStyle(
              color: Colors.white.withOpacity(0.45),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Lyrics Content View ──────────────────────────────────────────────────────

class _LyricsView extends ConsumerStatefulWidget {
  final LyricsState lyricsState;
  final ScrollController scroll;

  const _LyricsView({
    super.key,
    required this.lyricsState,
    required this.scroll,
  });

  @override
  ConsumerState<_LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends ConsumerState<_LyricsView> {
  int _activeIndex = -1;
  late List<GlobalKey> _lineKeys;
  /// True = auto-scroll mengikuti lirik aktif. False = user sedang manual scroll.
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _initKeys();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lyricsState.syncedLines != oldWidget.lyricsState.syncedLines) {
      _initKeys();
    }
  }

  void _initKeys() {
    final count = widget.lyricsState.syncedLines?.length ?? 0;
    _lineKeys = List.generate(count, (_) => GlobalKey());
  }

  /// Scroll ke baris lirik yang sedang aktif.
  void _scrollToActive() {
    if (_activeIndex < 0 || _activeIndex >= _lineKeys.length) return;
    final key = _lineKeys[_activeIndex];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    }
  }

  /// Aktifkan kembali auto-scroll dan langsung sync ke lirik aktif.
  void _syncNow() {
    setState(() => _autoScroll = true);
    _scrollToActive();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyricsState.hasSyncedLyrics) {
      final position = ref.watch(playerProvider.select((p) => p.position));
      final lines = widget.lyricsState.syncedLines!;

      int newIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (position >= lines[i].timestamp) {
          newIndex = i;
        } else {
          break;
        }
      }

      if (newIndex != _activeIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _activeIndex = newIndex);
            if (_autoScroll) _scrollToActive();
          }
        });
      }

      return Stack(
        children: [
          // ── ListView lirik dengan deteksi drag manual ──────────────────────
          NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              // UserScrollNotification hanya fire saat user BENAR-BENAR drag,
              // tidak fire saat programmatic scroll via _scrollToActive().
              if (notification.direction != ScrollDirection.idle) {
                if (_autoScroll) setState(() => _autoScroll = false);
              }
              return false;
            },
            child: Scrollbar(
              controller: widget.scroll,
              thumbVisibility: false,
              child: ListView.builder(
                controller: widget.scroll,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 300),
                itemCount: lines.length + 1,
                itemBuilder: (ctx, i) {
                  if (i == lines.length) return _buildFooter();
                  final isActive = i == _activeIndex;
                  return Padding(
                    key: _lineKeys[i],
                    padding: const EdgeInsets.only(bottom: 24),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: GoogleFonts.plusJakartaSans(
                        color: isActive
                            ? const Color(0xFFFFFFFF)
                            : const Color(0xFFFFFFFF).withOpacity(0.55),
                        fontSize: isActive ? 28 : 24,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w700,
                        height: 1.5,
                        letterSpacing: isActive ? 28 * -0.02 : 24 * -0.02,
                      ),
                      child: Text(lines[i].text),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Tombol Sync — muncul hanya saat user sudah manual scroll ───────
          // Posisi: tengah-bawah, style Spotify (putih, pill, equalizer icon)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: AnimatedOpacity(
              opacity: _autoScroll ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: _autoScroll,
                child: Center(
                  child: GestureDetector(
                    onTap: _syncNow,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.graphic_eq_rounded,
                            color: Colors.black,
                            size: 16,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'Sync',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Fallback: Plain lyrics mode
    final lyrics = widget.lyricsState.lyrics!;
    final paragraphs = lyrics
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    final blocks = paragraphs.isEmpty
        ? lyrics.split('\n').where((l) => l.trim().isNotEmpty).toList()
        : paragraphs;

    return Scrollbar(
      controller: widget.scroll,
      thumbVisibility: false,
      child: ListView.builder(
        controller: widget.scroll,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
        itemCount: blocks.length + 1,
        itemBuilder: (ctx, i) {
          if (i == blocks.length) return _buildFooter();
          return _LyricParagraph(text: blocks[i]);
        },
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Akhir lirik',
            style: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single lyrics paragraph/stanza block.
class _LyricParagraph extends StatelessWidget {
  final String text;

  const _LyricParagraph({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          color: const Color(0xFFFFFFFF).withOpacity(0.55),
          fontSize: 17,
          fontWeight: FontWeight.w600,
          height: 1.65,
          letterSpacing: 17 * -0.02,
        ),
      ),
    );
  }
}

// ─── Manual Lyrics Input View ─────────────────────────────────────────────────
// Ditampilkan ketika tidak ada lirik (embedded maupun API).
// Song dikirim via constructor — tidak ada ref.watch di sini untuk menghindari
// _dependents.isEmpty assertion saat AnimatedSwitcher sedang menganimasi.

class _ManualLyricsInputView extends ConsumerStatefulWidget {
  final dynamic song;

  const _ManualLyricsInputView({super.key, this.song});

  @override
  ConsumerState<_ManualLyricsInputView> createState() =>
      _ManualLyricsInputViewState();
}

class _ManualLyricsInputViewState
    extends ConsumerState<_ManualLyricsInputView> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final text = _controller.text.trim();
    if (text.length < 5) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      // saveManualLyrics parse + simpan + update state otomatis ke found
      await ref.read(lyricsProvider.notifier).saveManualLyrics(text);
      // State provider berubah → AnimatedSwitcher otomatis switch ke _LyricsView
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Insets keyboard agar konten tidak tertutup saat keyboard muncul
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.08),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Icon(
                    Icons.lyrics_outlined,
                    color: Colors.white.withOpacity(0.5),
                    size: 26,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Belum ada lirik',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.song != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    'untuk "${widget.song.title}"',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(lyricsProvider.notifier).refresh();
                    },
                    icon: const Icon(Icons.refresh_rounded, 
                        size: 16, color: AppColors.primary),
                    label: const Text(
                      'Coba Cari Ulang',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  
                  // Debug Info
                  Consumer(
                    builder: (context, ref, child) {
                      final state = ref.watch(lyricsProvider);
                      if (state.debugMessage != null) {
                        return Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Text(
                            'DEBUG INFO:\n${state.debugMessage}',
                            style: TextStyle(
                              color: Colors.red.shade200,
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Label ───────────────────────────────────────────────────────────
          Text(
            'TULIS ATAU TEMPEL LIRIK',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),

          // ── TextField ───────────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.white.withOpacity(0.12)),
            ),
            child: TextField(
              controller: _controller,
              maxLines: null,
              minLines: 9,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.65,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText:
                    'Bila ini kesempatan kamu\nRemedi yang mungkin tak terulang\n\n(Gunakan baris kosong untuk memisahkan bait)',
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.22),
                  fontSize: 13,
                  height: 1.65,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // ── Tip ─────────────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.white.withOpacity(0.3), size: 13),
              const SizedBox(width: 6),
              Text(
                'Baris kosong = pemisah bait. Lirik disimpan permanen.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Save Button ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _handleSave,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan Lirik'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white38,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini Player Footer ─────────────────────────────────────────────────────
/// Footer bergaya Spotify di bagian bawah LyricsScreen:
/// - Baris atas  : album art kecil + judul + artist + tombol tambah
/// - Seek bar    : dengan timestamp kiri/kanan
/// - Controls    : prev / play-pause (besar) / next di tengah
class _MiniPlayerFooter extends ConsumerWidget {
  final dynamic song;

  const _MiniPlayerFooter({this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong ?? song;
    if (currentSong == null) return const SizedBox.shrink();

    final progress = playerState.duration.inMilliseconds > 0
        ? (playerState.position.inMilliseconds /
                playerState.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        // Gunakan gradasi transparan ke sedikit gelap agar menyatu sempurna dengan background layar
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withOpacity(0.4),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Baris 1 dihapus (album art + judul + artist) ─────────────────
          // Cukup tampilkan slider dan kontrol playback sesuai spesifikasi.

          // ── Baris 2: Seek bar ───────────────────────────────────────────
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white.withOpacity(0.25),
              thumbColor: Colors.white,
            ),
            child: Slider(
              value: progress,
              onChanged: (v) {
                final ms = (v * playerState.duration.inMilliseconds).round();
                ref
                    .read(playerProvider.notifier)
                    .seekToDuration(Duration(milliseconds: ms));
              },
            ),
          ),

          // Timestamps
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(playerState.position),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  _fmt(playerState.duration),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Baris 3: Kontrol prev / play-pause / next ───────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Previous
              GestureDetector(
                onTap: () =>
                    ref.read(playerProvider.notifier).previousTrack(),
                child: Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white.withOpacity(0.85),
                  size: 36,
                ),
              ),

              const SizedBox(width: 28),

              // Play / Pause (besar, lingkaran putih)
              GestureDetector(
                onTap: () =>
                    ref.read(playerProvider.notifier).togglePlay(),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    playerState.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 30,
                  ),
                ),
              ),

              const SizedBox(width: 28),

              // Next
              GestureDetector(
                onTap: () =>
                    ref.read(playerProvider.notifier).nextTrack(),
                child: Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white.withOpacity(0.85),
                  size: 36,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
