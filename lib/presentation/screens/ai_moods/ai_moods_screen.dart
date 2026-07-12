import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/gemini_datasource.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../../../services/download_service.dart';

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

        // ── Suggestion chips (Dipindah ke atas pesan) ─────────────────────────
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: (!chatState.isLoading && chatState.messages.length == 1 && dlState.messages.isEmpty)
              ? _SuggestionBar(
                  key: const ValueKey('suggestions'),
                  onTap: (text) {
                    if (text == '__download__') {
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
              IconButton(
                onPressed: () => _showDebugLogsSheet(context),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.bug_report_rounded,
                    color: AppColors.primary, size: 20),
                tooltip: 'Show Debug Logs',
              ),
              const SizedBox(width: 8),
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

class _MessageBubble extends ConsumerWidget {
  final AIChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
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
                  if (isAI && message.recommendedSongs != null && message.recommendedSongs!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 8),
                    ...message.recommendedSongs!.map((song) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SongArtworkWidget(
                              song: song,
                              size: 32,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  song.title,
                                  style: const TextStyle(
                                    color: AppColors.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  song.artist,
                                  style: const TextStyle(
                                    color: AppColors.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.play_arrow_rounded, color: AppColors.primary, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              ref.read(playerProvider.notifier).playSong(song, message.recommendedSongs!);
                            },
                          ),
                        ],
                      ),
                    )),
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

// ─── Typing Bubble (M3) ──────────────────────────────────────────────────

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
        vsync: this, duration: const Duration(milliseconds: 1000))
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
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.surfaceContainerHigh,
            ),
            child: const Icon(Icons.search_rounded, color: AppColors.primary, size: 16),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => Row(
                children: [
                  Icon(Icons.circle, size: 6, color: AppColors.primary.withOpacity(0.5 + 0.5 * math.sin(_ctrl.value * 2 * math.pi))),
                  const SizedBox(width: 4),
                  Icon(Icons.circle, size: 6, color: AppColors.primary.withOpacity(0.5 + 0.5 * math.sin((_ctrl.value + 0.3) * 2 * math.pi))),
                  const SizedBox(width: 4),
                  Icon(Icons.circle, size: 6, color: AppColors.primary.withOpacity(0.5 + 0.5 * math.sin((_ctrl.value + 0.6) * 2 * math.pi))),
                ],
              ),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
    // (icon, label, sentText) — Download Music SELALU PERTAMA
    final chips = [
      (Icons.download_rounded,       'Download Music',   '__download__'),
      (Icons.code_rounded,           'Stres ngoding',    'Stres ngoding'),
      (Icons.menu_book_rounded,      'Semangat belajar', 'Semangat belajar'),
      (Icons.weekend_rounded,        'Santai weekend',   'Santai weekend'),
      (Icons.water_drop_rounded,     'Hujan melamun',    'Hujan melamun'),
      (Icons.heart_broken_rounded,   'Lagi galau',       'Lagi galau'),
      (Icons.local_fire_department_rounded, 'Hype banget', 'Hype banget'),
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
                icon: c.$1,
                label: c.$2,
                isDownload: c.$3 == '__download__',
                onTap: () => onTap(c.$3),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isDownload;
  final VoidCallback onTap;
  const _SuggestionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDownload = false,
  });

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: widget.isDownload
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isDownload
                  ? AppColors.primary.withOpacity(0.6)
                  : AppColors.primary.withOpacity(0.2),
              width: widget.isDownload ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isDownload
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isDownload
                      ? AppColors.primary
                      : AppColors.onSurface,
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
// Tampilan identik dengan bubble AI (kiri, avatar, surfaceContainerHigh)
// agar terasa native sebagai bagian dari chat, bukan elemen asing.

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
    final status = progress?.status ?? DownloadStatus.idle;
    final isSearching = isProgress &&
        (status == DownloadStatus.idle ||
            status == DownloadStatus.fetchingMetadata ||
            (status == DownloadStatus.downloading && pct < 1.0));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 52),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar — sama persis seperti AI bubble tapi pakai ikon download
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
            child: const Icon(Icons.download_rounded,
                color: Colors.white, size: 15),
          ),

          // Bubble — sama persis seperti AI bubble
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animasi equalizer saat pencarian / proses awal
                  if (isSearching) ...[
                    _MusicEqualizerAnimation(),
                    const SizedBox(height: 8),
                  ],

                  // Teks pesan dengan bold support
                  _RichDownloadText(text: message.content),

                  // Progress bar saat downloading
                  if (isProgress &&
                      status == DownloadStatus.downloading &&
                      pct > 0) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct / 100.0,
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  // Converting / tagging: indeterminate progress
                  if (isProgress &&
                      (status == DownloadStatus.converting ||
                          status == DownloadStatus.tagging)) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],

                  // Tombol Debug Logs selalu ditampilkan agar bisa dilihat jika gagal atau selesai
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => _showDebugLogsSheet(context),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.bug_report_rounded,
                            size: 13,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Lihat Log Debug',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Music Equalizer Animation ────────────────────────────────────────────────
// Animasi 4 bar equalizer bergerak naik-turun saat proses pencarian musik.

class _MusicEqualizerAnimation extends StatefulWidget {
  const _MusicEqualizerAnimation();

  @override
  State<_MusicEqualizerAnimation> createState() =>
      _MusicEqualizerAnimationState();
}

class _MusicEqualizerAnimationState extends State<_MusicEqualizerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  static const _barCount = 5;
  // Setiap bar punya phase offset berbeda agar gerakannya asinkron
  static const _phases = [0.0, 0.25, 0.5, 0.75, 0.15];

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
          ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(_barCount, (i) {
            final phase = (_ctrl.value + _phases[i]) % 1.0;
            final height = 4.0 + (math.sin(phase * math.pi * 2) + 1) / 2 * 14.0;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.85),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─── Rich Download Text ───────────────────────────────────────────────────────
// Render teks dengan **bold** markers — tanpa emoji.

class _RichDownloadText extends StatelessWidget {
  final String text;
  const _RichDownloadText({required this.text});

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'\*\*(.*?)\*\*');
    int last = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(
          text: text.substring(last, match.start),
          style: const TextStyle(
            color: AppColors.onSurface,
            fontSize: 14,
            height: 1.55,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(
          color: AppColors.onSurface,
          fontSize: 14,
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
          fontSize: 14,
          height: 1.55,
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }
}

void _showDebugLogsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _DebugLogsSheet(),
  );
}

class _DebugLogsSheet extends StatefulWidget {
  const _DebugLogsSheet();

  @override
  State<_DebugLogsSheet> createState() => _DebugLogsSheetState();
}

class _DebugLogsSheetState extends State<_DebugLogsSheet> {
  String _logText = 'Memuat log...';
  bool _isLoading = true;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
    });
    final logs = await DownloadService.instance.getDownloadLog();
    if (mounted) {
      setState(() {
        _logText = logs;
        _isLoading = false;
      });
      // Scroll to bottom after layout
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _logText)).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Log berhasil disalin ke clipboard!'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      height: MediaQuery.of(context).size.height * 0.8,
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Download Debug Logs',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Detail log proses download & error yt-dlp',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Refresh Button
                IconButton(
                  onPressed: _isLoading ? null : _loadLogs,
                  icon: _isLoading 
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded, color: Colors.white),
                  tooltip: 'Segarkan log',
                ),
                
                // Copy Button
                IconButton(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy_all_rounded, color: AppColors.primary),
                  tooltip: 'Salin semua log',
                ),
                
                // Close Button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'Tutup',
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          
          // Log Text Box
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF070707),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: _isLoading 
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : SingleChildScrollView(
                    controller: _scrollCtrl,
                    child: SelectionArea(
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          _logText.isEmpty ? 'Belum ada log yang tercatat.' : _logText,
                          style: TextStyle(
                            color: _logText.contains('[ERROR]') ? Colors.red[300] : Colors.green[300],
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
