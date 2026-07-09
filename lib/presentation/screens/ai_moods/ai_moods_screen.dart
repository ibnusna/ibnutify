import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/gemini_datasource.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';

/// AI Moods — Material You / Material Design 3
/// Tonal surfaces, rounded-28 cards, smooth spring animations.
class AIMoodsScreen extends ConsumerStatefulWidget {
  const AIMoodsScreen({super.key});

  @override
  ConsumerState<AIMoodsScreen> createState() => _AIMoodsScreenState();
}

class _AIMoodsScreenState extends ConsumerState<AIMoodsScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _inputBarAnim;

  @override
  void initState() {
    super.initState();
    _inputBarAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _inputBarAnim.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    final dlState = ref.read(downloadProvider);

    // Jika sedang dalam mode menunggu URL Spotify
    if (dlState.awaitingUrl) {
      ref.read(downloadProvider.notifier).handleUserInput(text);
      _scrollToBottom();
      return;
    }

    // Jika user mengetik URL Spotify langsung (tanpa tekan chip)
    if (text.contains('open.spotify.com/track/') || text.contains('spotify:track:')) {
      ref.read(downloadProvider.notifier).handleUserInput(text);
      _scrollToBottom();
      return;
    }

    // Rute normal ke AI chat
    ref.read(aiChatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiChatProvider);
    final dlState = ref.watch(downloadProvider);

    ref.listen<AIChatState>(aiChatProvider, (_, next) {
      if (!next.isLoading) _scrollToBottom();
    });

    return Column(
      children: [
        // ── M3 Top App Bar ────────────────────────────────────────────────────
        _M3TopBar(
          onClear: () {
            ref.read(aiChatProvider.notifier).clearChat();
            ref.read(downloadProvider.notifier).clearMessages();
          },
        ),

        // ── Messages ──────────────────────────────────────────────────────────
        Expanded(
          child: Builder(builder: (context) {
            final dlMessages = dlState.messages;
            final aiMessages = chatState.messages;

            // Total item: AI messages + download messages + loading/pending
            final aiCount = aiMessages.length;
            final dlCount = dlMessages.length;
            final loadingOffset = chatState.isLoading ? 1 : 0;
            final pendingOffset = chatState.pendingSongs != null ? 1 : 0;
            final totalCount = aiCount + dlCount + loadingOffset + pendingOffset;

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: totalCount,
              itemBuilder: (ctx, i) {
                // AI messages first
                if (i < aiCount) {
                  return _AnimatedEntry(
                    delay: Duration(milliseconds: i * 40),
                    child: _MessageBubble(message: aiMessages[i]),
                  );
                }

                // Typing indicator
                if (chatState.isLoading && i == aiCount) {
                  return const _TypingBubble();
                }

                // Pending playlist card
                if (chatState.pendingSongs != null &&
                    i == aiCount + loadingOffset) {
                  return _AnimatedEntry(
                    child: _PlaylistCard(
                      songs: chatState.pendingSongs!,
                      playlistName: chatState.pendingPlaylistName ?? 'AI Mix',
                      onTap: () => ref
                          .read(aiChatProvider.notifier)
                          .createPlaylistFromPending(),
                    ),
                  );
                }

                // Download system messages
                final dlIdx = i - aiCount - loadingOffset - pendingOffset;
                if (dlIdx >= 0 && dlIdx < dlCount) {
                  final dlMsg = dlMessages[dlIdx];
                  return _AnimatedEntry(
                    delay: Duration(milliseconds: dlIdx * 40),
                    child: _DownloadSystemBubble(
                      message: dlMsg,
                      isProgress: dlMsg.isProgress,
                    ),
                  );
                }

                return const SizedBox.shrink();
              },
            );
          }),
        ),

        // ── Suggestion chips (only on fresh state) ────────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: (!chatState.isLoading && chatState.messages.length == 1 && dlState.messages.isEmpty)
              ? _SuggestionBar(
                  key: const ValueKey('suggestions'),
                  onTap: (text) {
                    if (text == '🎵 Download Music') {
                      ref.read(downloadProvider.notifier).requestUrl();
                      _scrollToBottom();
                      return;
                    }
                    _controller.text = text;
                    _sendMessage();
                  },
                )
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),

        // ── M3 Input Bar ──────────────────────────────────────────────────────
        _M3InputBar(
          controller: _controller,
          isLoading: chatState.isLoading || dlState.isDownloading,
          hintText: dlState.awaitingUrl
              ? 'Paste link Spotify di sini...'
              : 'Ceritakan mood atau kebutuhan lagu...',
          onSend: _sendMessage,
        ),
      ],
    );
  }
}

// ─── M3 Top App Bar ──────────────────────────────────────────────────────────

class _M3TopBar extends StatelessWidget {
  final VoidCallback onClear;
  const _M3TopBar({required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              // Leading icon + title
              Expanded(
                child: Row(
                  children: [
                    Container(
                      margin: const EdgeInsets.all(8),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.primary,
                            const Color(0xFF0D9C46),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Moods',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Playlist personal berbasis AI',
                          style: TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Trailing: reset button (M3 icon button)
              IconButton(
                onPressed: onClear,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.restart_alt_rounded,
                    color: AppColors.onSurfaceVariant, size: 20),
                tooltip: 'Reset chat',
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Animated entry wrapper ───────────────────────────────────────────────────

class _AnimatedEntry extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _AnimatedEntry({required this.child, this.delay = Duration.zero});

  @override
  State<_AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<_AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}

// ─── Message Bubble (Material You) ───────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final AIChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isAI = message.role == ChatRole.ai;

    return Padding(
      padding: EdgeInsets.only(
        bottom: 10,
        left: isAI ? 0 : 52,
        right: isAI ? 52 : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          // AI avatar
          if (isAI) ...[
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, Color(0xFF0D9C46)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 15),
            ),
          ],
          // Bubble
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                // M3 tonal surface for AI, primary-container for user
                color: isAI
                    ? AppColors.surfaceContainerHigh
                    : AppColors.primary.withOpacity(0.18),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isAI ? 4 : 20),
                  bottomRight: Radius.circular(isAI ? 20 : 4),
                ),
                border: isAI
                    ? null
                    : Border.all(
                        color: AppColors.primary.withOpacity(0.35),
                        width: 1,
                      ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isAI
                      ? AppColors.onSurface
                      : AppColors.primary.withOpacity(0.95),
                  fontSize: 14,
                  height: 1.55,
                  fontWeight:
                      isAI ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Typing Bubble ───────────────────────────────────────────────────────────

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8, bottom: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [AppColors.primary, Color(0xFF0D9C46)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 15),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _ctrl,
                  builder: (_, __) {
                    final phase = (_ctrl.value - i * 0.18).clamp(0.0, 1.0);
                    final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 7,
                      height: 7 + pulse * 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary
                            .withOpacity(0.4 + pulse * 0.6),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Playlist Card (M3 Filled Card) ──────────────────────────────────────────

class _PlaylistCard extends StatelessWidget {
  final List<SongModel> songs;
  final String playlistName;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.songs,
    required this.playlistName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, left: 40, right: 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.25),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Song artwork grid strip
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  ...songs.take(5).map(
                        (s) => Expanded(
                          child: SongArtworkWidget(
                            song: s,
                            size: double.infinity,
                            borderRadius: 0,
                          ),
                        ),
                      ),
                  if (songs.length < 5)
                    ...List.generate(
                      5 - songs.length,
                      (_) => Expanded(
                        child: Container(
                          color: AppColors.surfaceContainerHighest,
                          child: const Icon(Icons.music_note_rounded,
                              color: AppColors.onSurfaceVariant, size: 20),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Info + button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Playlist name
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.primary, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          playlistName,
                          style: const TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${songs.length} lagu dipilih oleh AI',
                    style: const TextStyle(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // M3 Filled Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.playlist_add_check_rounded,
                          size: 18),
                      label: const Text(
                        'Masukkan ke Playlist',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
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
}

// ─── Suggestion Bar ───────────────────────────────────────────────────────────

class _SuggestionBar extends StatelessWidget {
  final ValueChanged<String> onTap;
  const _SuggestionBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final chips = [
      ('😮‍💨', 'Stres ngoding'),
      ('📚', 'Semangat belajar'),
      ('😎', 'Santai weekend'),
      ('🌧️', 'Hujan melamun'),
      ('💔', 'Lagi galau'),
      ('🔥', 'Hype banget'),
      ('🎵', 'Download Music'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: chips.map((c) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SuggestionChip(
                emoji: c.$1,
                label: c.$2,
                onTap: () => onTap('${c.$1} ${c.$2}'),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip(
      {required this.emoji, required this.label, required this.onTap});

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.93,
        upperBound: 1.0,
        value: 1.0);
    _scale = _ctrl;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.reverse(),
        onTapUp: (_) {
          _ctrl.forward();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.forward(),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.2), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.emoji,
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── M3 Input Bar ─────────────────────────────────────────────────────────────

class _M3InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSend;
  final String hintText;

  const _M3InputBar({
    required this.controller,
    required this.isLoading,
    required this.onSend,
    this.hintText = 'Ceritakan mood atau kebutuhan lagu...',
  });

  @override
  State<_M3InputBar> createState() => _M3InputBarState();
}

class _M3InputBarState extends State<_M3InputBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _btnAnim;
  late Animation<double> _btnScale;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _btnAnim = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.88,
        upperBound: 1.0,
        value: 1.0);
    _btnScale = _btnAnim;
    widget.controller.addListener(() {
      final hasText = widget.controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _btnAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant.withOpacity(0.98),
        border: Border(
          top: BorderSide(
              color: Colors.white.withOpacity(0.06), width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Text field — M3 OutlinedTextField style
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _hasText
                          ? AppColors.primary.withOpacity(0.5)
                          : Colors.white.withOpacity(0.08),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 14,
                        height: 1.4),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) => widget.onSend(),
                    enabled: !widget.isLoading,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Send button — M3 Filled Icon Button
              ScaleTransition(
                scale: _btnScale,
                child: GestureDetector(
                  onTapDown: widget.isLoading
                      ? null
                      : (_) => _btnAnim.reverse(),
                  onTapUp: widget.isLoading
                      ? null
                      : (_) {
                          _btnAnim.forward();
                          widget.onSend();
                        },
                  onTapCancel: () => _btnAnim.forward(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: (widget.isLoading || !_hasText)
                          ? AppColors.surfaceContainerHighest
                          : AppColors.primary,
                    ),
                    child: widget.isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(13),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(
                            Icons.send_rounded,
                            color: _hasText
                                ? Colors.white
                                : AppColors.onSurfaceVariant,
                            size: 20,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Download System Bubble ───────────────────────────────────────────────────
// Menampilkan pesan dari sistem downloader (bukan AI dan bukan user).
// Desain: lebar penuh dengan border hijau, ikon download, dan teks bold.

class _DownloadSystemBubble extends StatelessWidget {
  final DownloadChatMessage message;
  final bool isProgress;

  const _DownloadSystemBubble({
    required this.message,
    this.isProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final progress = message.progress;
    final pct = progress?.percent ?? 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // System icon
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8, top: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                colors: [Color(0xFF1DB954), Color(0xFF0D9C46)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.download_rounded,
              color: Colors.white,
              size: 15,
            ),
          ),

          // Bubble
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
                ),
                border: Border.all(
                  color: const Color(0xFF1DB954).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Teks pesan — render **bold** secara manual
                  _RichDownloadText(text: message.content),

                  // Progress bar (hanya saat isProgress dan ada persen)
                  if (isProgress && pct > 0) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct / 100.0,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF1DB954),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Render teks dengan **bold** markers menjadi TextSpan.
class _RichDownloadText extends StatelessWidget {
  final String text;
  const _RichDownloadText({required this.text});

  @override
  Widget build(BuildContext context) {
    // Split by **...**
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int last = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: text.substring(last, match.start),
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 13.5,
            height: 1.55,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 13.5,
          height: 1.55,
          fontWeight: FontWeight.w700,
        ),
      ));
      last = match.end;
    }

    if (last < text.length) {
      spans.add(TextSpan(
        text: text.substring(last),
        style: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 13.5,
          height: 1.55,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }
}
