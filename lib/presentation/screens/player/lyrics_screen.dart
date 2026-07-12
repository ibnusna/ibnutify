import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/album_art_service.dart';
import '../../providers/app_providers.dart';
import '../../providers/album_art_provider.dart';
import '../../providers/lyrics_provider.dart';

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
                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: blended.length >= 3
                          ? [
                              // Darken significantly for readability
                              _darken(blended[0], 0.7),
                              _darken(blended[1], 0.8),
                              _darken(blended.last, 0.9),
                            ]
                          : [
                              _darken(blended.first, 0.7),
                              _darken(blended.last, 0.9),
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
                      Colors.black.withOpacity(0.25),
                      Colors.black.withOpacity(0.40),
                      Colors.black.withOpacity(0.55),
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

  @override
  void initState() {
    super.initState();
    _initKeys();
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

  void _scrollToActive() {
    if (_activeIndex < 0 || _activeIndex >= _lineKeys.length) return;
    
    final key = _lineKeys[_activeIndex];
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3, // 0.0 is top, 0.5 is center. 0.3 keeps it slightly above center.
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyricsState.hasSyncedLyrics) {
      // Syncing LRC mode
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
            setState(() {
              _activeIndex = newIndex;
            });
            _scrollToActive();
          }
        });
      }

      return Scrollbar(
        controller: widget.scroll,
        thumbVisibility: false,
        child: ListView.builder(
          controller: widget.scroll,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 300), // Extra bottom padding
          itemCount: lines.length + 1,
          itemBuilder: (ctx, i) {
            if (i == lines.length) return _buildFooter();
            final isActive = i == _activeIndex;
            return Padding(
              key: _lineKeys[i],
              padding: const EdgeInsets.only(bottom: 24),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
                  fontSize: isActive ? 28 : 24,
                  fontWeight: FontWeight.w800,
                  height: 1.5,
                  letterSpacing: 0.1,
                ),
                child: Text(lines[i].text),
              ),
            );
          },
        ),
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
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.65,
          letterSpacing: 0.1,
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
