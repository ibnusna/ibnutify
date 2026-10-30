import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/datasources/gemini_datasource.dart';
import '../../../data/models/song_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/common/song_artwork_widget.dart';
import '../../../services/download_service.dart';
import '../../../services/chat_history_service.dart';


// ─────────────────────────────────────────────────────────────────────────────
// AIMoodsScreen — Gemini-style fluid layout
// Sepenuhnya mengikuti prototype HTML ibnutify_ai_prototype.html secara 1:1.
// Layout: Stack(AmbientBackground, Column(FloatingHeader, ChatArea, InputBar))
// ─────────────────────────────────────────────────────────────────────────────

class AIMoodsScreen extends ConsumerStatefulWidget {
  const AIMoodsScreen({super.key});

  @override
  ConsumerState<AIMoodsScreen> createState() => _AIMoodsScreenState();
}

class _AIMoodsScreenState extends ConsumerState<AIMoodsScreen>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // ── Local UI state (tidak perlu provider) ──────────────────────────────────
  bool _sidebarOpen = false;
  bool _isHeroVisible = true; // AI Hero hilang saat pesan pertama dikirim
  String _currentGreeting = '';

  static const _greetings = [
    'Apa yang ingin didengarkan hari ini?',
    'Ada lagu yang ingin di-download?',
    'Mari buat playlist untuk harimu.',
    'Ceritakan mood-mu, biar AI yang pilihkan lagu.',
    'Paste link Spotify, saya yang urus sisanya.',
  ];

  @override
  void initState() {
    super.initState();
    _currentGreeting = _greetings[math.Random().nextInt(_greetings.length)];
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Scroll helpers ─────────────────────────────────────────────────────────

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

  // ── Intent router ─────────────────────────────────────────────────────────

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    // Hero hilang saat pesan pertama dikirim
    if (_isHeroVisible) {
      setState(() => _isHeroVisible = false);
    }

    debugPrint('[AIMoods.Intent] Input: "$text"');

    final dlState = ref.read(downloadProvider);

    // Jika sedang menunggu URL Spotify
    if (dlState.awaitingUrl) {
      debugPrint('[AIMoods.Intent] Routing: awaitingUrl mode');
      // [BUG-1 FIX] Tampilkan pesan user di chat sebelum routing ke downloader
      ref.read(aiChatProvider.notifier).addUserMessageOnly(
        AIChatMessage(role: ChatRole.user, content: text),
      );
      ref.read(downloadProvider.notifier).handleUserInput(text);
      _scrollToBottom();
      return;
    }

    // Deteksi otomatis URL Spotify (track atau playlist)
    if (DownloadService.isSpotifyUrl(text)) {
      debugPrint('[AIMoods.Intent] Routing: Spotify URL detected');
      // [BUG-1 FIX] Tampilkan gelembung chat kanan (user) sebelum memulai download
      ref.read(aiChatProvider.notifier).addUserMessageOnly(
        AIChatMessage(role: ChatRole.user, content: text),
      );
      ref.read(downloadProvider.notifier).handleUserInput(text);
      _scrollToBottom();
      return;
    }

    // Rute normal ke AI chat
    debugPrint('[AIMoods.Intent] Routing: AI chat');
    ref.read(aiChatProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }


  // ── Sidebar helpers ────────────────────────────────────────────────────────

  void _openSidebar() {
    setState(() => _sidebarOpen = true);
    // Refresh history saat sidebar dibuka
    ref.read(chatHistoryProvider.notifier).refresh();
  }

  void _closeSidebar() => setState(() => _sidebarOpen = false);

  void _startNewChat() {
    _closeSidebar();
    ref.read(aiChatProvider.notifier).clearChat();
    ref.read(downloadProvider.notifier).clearMessages();
    setState(() {
      _isHeroVisible = true;
      _currentGreeting = _greetings[math.Random().nextInt(_greetings.length)];
    });
  }

  void _loadSession(ChatSession session) {
    _closeSidebar();
    ref.read(aiChatProvider.notifier).restoreSession(session);
    ref.read(downloadProvider.notifier).clearMessages();
    setState(() => _isHeroVisible = false);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(aiChatProvider);
    final dlState = ref.watch(downloadProvider);

    ref.listen<AIChatState>(aiChatProvider, (_, next) {
      if (!next.isLoading) _scrollToBottom();
    });
    ref.listen<DownloadState>(downloadProvider, (_, next) {
      if (!next.isDownloading) _scrollToBottom();
    });

    return Stack(
      children: [
        // ── Layer 0: Ambient Background ──────────────────────────────────────
        const _AmbientBackground(),

        // ── Layer 1: Main content ────────────────────────────────────────────
        Stack(
          children: [
            Column(
              children: [
                // Floating Header
                _FloatingAIHeader(
                  onSidebarTap: _openSidebar,
                  onNewChat: _startNewChat,
                ),

                // Chat Messages
                Expanded(
                  child: _ChatArea(
                    scrollController: _scrollController,
                    chatState: chatState,
                    dlState: dlState,
                    isHeroVisible: _isHeroVisible,
                    greeting: _currentGreeting,
                  ),
                ),
              ],
            ),

            // Input Bar (Floating at bottom)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _FluidInputBar(
                controller: _controller,
                isLoading: chatState.isLoading || dlState.isDownloading,
                isDownloading: dlState.isDownloading,
                hintText: dlState.awaitingUrl
                    ? 'Paste link Spotify di sini...'
                    : 'Tanya sesuatu atau paste link Spotify...',
                onSend: _sendMessage,
                onCancelDownload: () {
                  ref.read(downloadProvider.notifier).cancelCurrentDownload();
                },
              ),
            ),
          ],
        ),

        // ── Layer 2: Sidebar overlay + sidebar (Must be on top) ─────────────
        _SidebarOverlay(visible: _sidebarOpen, onTap: _closeSidebar),
        _ChatHistorySidebar(
          open: _sidebarOpen,
          onClose: _closeSidebar,
          onNewChat: _startNewChat,
          onLoadSession: _loadSession,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AMBIENT BACKGROUND — 2 blur blobs yang bergerak lambat seperti HTML prototype
// ─────────────────────────────────────────────────────────────────────────────

class _AmbientBackground extends StatefulWidget {
  const _AmbientBackground();
  @override
  State<_AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<_AmbientBackground>
    with TickerProviderStateMixin {
  late AnimationController _blob1Ctrl;
  late AnimationController _blob2Ctrl;
  late Animation<Offset> _blob1Pos;
  late Animation<Offset> _blob2Pos;

  @override
  void initState() {
    super.initState();
    _blob1Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);

    _blob2Ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);

    _blob1Pos = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0.15, 0.1),
    ).animate(CurvedAnimation(parent: _blob1Ctrl, curve: Curves.easeInOut));

    _blob2Pos = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(-0.1, -0.12),
    ).animate(CurvedAnimation(parent: _blob2Ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _blob1Ctrl.dispose();
    _blob2Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: Listenable.merge([_blob1Ctrl, _blob2Ctrl]),
        builder: (_, __) {
          return Stack(
            children: [
              // Blob 1 — primary green (top-left)
              Positioned(
                left: (-size.width * 0.1) + (_blob1Pos.value.dx * size.width),
                top: (-size.height * 0.1) + (_blob1Pos.value.dy * size.height),
                child: _Blob(
                  size: 300,
                  color: AppColors.primary.withOpacity(0.3),
                ),
              ),
              // Blob 2 — deeper green (bottom-right)
              Positioned(
                right: (-size.width * 0.1) + (_blob2Pos.value.dx.abs() * size.width * 0.5),
                bottom: (size.height * 0.2) + (_blob2Pos.value.dy.abs() * size.height * 0.1),
                child: _Blob(
                  size: 250,
                  color: const Color(0xFF1db954).withOpacity(0.3),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: const SizedBox(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLOATING AI HEADER — gradient fade, mood dot, menu + pencil icons
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingAIHeader extends StatelessWidget {
  final VoidCallback onSidebarTap;
  final VoidCallback onNewChat;
  const _FloatingAIHeader({
    required this.onSidebarTap,
    required this.onNewChat,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.background.withOpacity(0.95),
            AppColors.background.withOpacity(0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Menu button
              _IconBtn(
                onTap: onSidebarTap,
                child: const Icon(Icons.menu_rounded,
                    color: AppColors.onSurface, size: 24),
              ),

              // Title + pulsing dot
              Row(
                children: [
                  const _PulsingDot(),
                  const SizedBox(width: 8),
                  const Text(
                    'AI Moods',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              // New chat (pencil) button
              _IconBtn(
                onTap: onNewChat,
                child: const Icon(Icons.edit_note_rounded,
                    color: AppColors.onSurface, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _IconBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PULSING DOT — indikator AI aktif seperti di prototype HTML
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.5).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _scale = Tween<double>(begin: 1.0, end: 0.8).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.6),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR OVERLAY — backdrop blur dimmer
// ─────────────────────────────────────────────────────────────────────────────

class _SidebarOverlay extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;
  const _SidebarOverlay({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !visible,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            color: Colors.black.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR — riwayat obrolan dengan judul sesungguhnya dari SharedPreferences
// ─────────────────────────────────────────────────────────────────────────────

class _ChatHistorySidebar extends ConsumerWidget {
  final bool open;
  final VoidCallback onClose;
  final VoidCallback onNewChat;
  final ValueChanged<ChatSession> onLoadSession;

  const _ChatHistorySidebar({
    required this.open,
    required this.onClose,
    required this.onNewChat,
    required this.onLoadSession,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(chatHistoryProvider);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: open ? 0 : -320,
      top: 0,
      bottom: 0,
      width: 300,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(10, 0),
            ),
          ],
          border: Border(
            right: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Riwayat',
                      style: TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.onSurface, size: 20),
                    ),
                  ],
                ),
              ),

              // New chat button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: onNewChat,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded,
                            color: AppColors.onSurface, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Obrolan Baru',
                          style: TextStyle(
                            color: AppColors.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // History List
              Expanded(
                child: historyAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
                  error: (_, __) => const Center(
                    child: Text('Gagal memuat riwayat',
                        style: TextStyle(
                            color: AppColors.onSurfaceVariant, fontSize: 13)),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const Center(
                        child: Text(
                          'Belum ada riwayat obrolan.',
                          style: TextStyle(
                              color: AppColors.onSurfaceVariant, fontSize: 13),
                        ),
                      );
                    }

                    // Group by Hari Ini / Kemarin / Lebih Lama
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final yesterday = today.subtract(const Duration(days: 1));

                    final todaySessions = sessions.where((s) {
                      final d = DateTime(s.createdAt.year, s.createdAt.month,
                          s.createdAt.day);
                      return d == today;
                    }).toList();
                    final yesterdaySessions = sessions.where((s) {
                      final d = DateTime(s.createdAt.year, s.createdAt.month,
                          s.createdAt.day);
                      return d == yesterday;
                    }).toList();
                    final olderSessions = sessions.where((s) {
                      final d = DateTime(s.createdAt.year, s.createdAt.month,
                          s.createdAt.day);
                      return d.isBefore(yesterday);
                    }).toList();

                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (todaySessions.isNotEmpty) ...[
                          _HistoryLabel('Hari Ini'),
                          ...todaySessions.map((s) => _HistoryItem(
                                session: s,
                                onTap: () => onLoadSession(s),
                                onDelete: () => ref
                                    .read(chatHistoryProvider.notifier)
                                    .deleteSession(s.id),
                              )),
                        ],
                        if (yesterdaySessions.isNotEmpty) ...[
                          _HistoryLabel('Kemarin'),
                          ...yesterdaySessions.map((s) => _HistoryItem(
                                session: s,
                                onTap: () => onLoadSession(s),
                                onDelete: () => ref
                                    .read(chatHistoryProvider.notifier)
                                    .deleteSession(s.id),
                              )),
                        ],
                        if (olderSessions.isNotEmpty) ...[
                          _HistoryLabel('Lebih Lama'),
                          ...olderSessions.map((s) => _HistoryItem(
                                session: s,
                                onTap: () => onLoadSession(s),
                                onDelete: () => ref
                                    .read(chatHistoryProvider.notifier)
                                    .deleteSession(s.id),
                              )),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryLabel extends StatelessWidget {
  final String text;
  const _HistoryLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final ChatSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _HistoryItem(
      {required this.session, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.03)),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline_rounded,
                size: 18, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                session.title,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT AREA — scroll container dengan hero, messages, dan loading indicators
// ─────────────────────────────────────────────────────────────────────────────

class _ChatArea extends StatelessWidget {
  final ScrollController scrollController;
  final AIChatState chatState;
  final DownloadState dlState;
  final bool isHeroVisible;
  final String greeting;

  const _ChatArea({
    required this.scrollController,
    required this.chatState,
    required this.dlState,
    required this.isHeroVisible,
    required this.greeting,
  });

  @override
  Widget build(BuildContext context) {
    final aiMessages = chatState.messages;
    final dlMessages = dlState.messages;
    final aiCount = aiMessages.length;
    final dlCount = dlMessages.length;
    final loadingOffset = chatState.isLoading ? 1 : 0;
    final pendingOffset = chatState.pendingSongs != null ? 1 : 0;
    final totalCount = aiCount + dlCount + loadingOffset + pendingOffset;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(
          left: 20, right: 20, top: 8, bottom: 160 // ruang untuk input + mini player
          ),
      itemCount: 1 + totalCount, // +1 untuk hero
      itemBuilder: (ctx, i) {
        // Item 0: Hero View (initial state)
        if (i == 0) {
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: isHeroVisible
                ? _AIHeroView(key: const ValueKey('hero'), greeting: greeting)
                : const SizedBox.shrink(key: ValueKey('empty')),
          );
        }

        final msgIdx = i - 1;

        // AI messages
        if (msgIdx < aiCount) {
          final msg = aiMessages[msgIdx];
          return _AnimatedEntry(
            delay: Duration(milliseconds: msgIdx * 40),
            child: msg.role == ChatRole.user
                ? _UserMessage(content: msg.content)
                : _AIMessage(message: msg),
          );
        }

        // Loading / thinking indicator
        if (chatState.isLoading && msgIdx == aiCount) {
          return const _StatusIndicator(
            text: 'Berpikir...',
            icon: Icons.auto_awesome_rounded,
          );
        }

        // Pending playlist card
        if (chatState.pendingSongs != null &&
            msgIdx == aiCount + loadingOffset) {
          return _AnimatedEntry(
            child: _PlaylistCard(
              songs: chatState.pendingSongs!,
              playlistName: chatState.pendingPlaylistName ?? 'AI Mix',
              onTap: () {},
            ),
          );
        }

        // Download system messages
        final dlIdx = msgIdx - aiCount - loadingOffset - pendingOffset;
        if (dlIdx >= 0 && dlIdx < dlCount) {
          final dlMsg = dlMessages[dlIdx];
          return _AnimatedEntry(
            delay: Duration(milliseconds: dlIdx * 40),
            child: _DownloadRichCard(message: dlMsg),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI HERO VIEW — initial state: sparkle logo + float + greeting text
// ─────────────────────────────────────────────────────────────────────────────

class _AIHeroView extends StatefulWidget {
  final String greeting;
  const _AIHeroView({super.key, required this.greeting});

  @override
  State<_AIHeroView> createState() => _AIHeroViewState();
}

class _AIHeroViewState extends State<_AIHeroView>
    with TickerProviderStateMixin {
  late AnimationController _entranceCtrl;
  late AnimationController _floatCtrl;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;
  late Animation<double> _logoRotate;
  late Animation<double> _floatY;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));

    // Logo reveal: fade + scale + spin entrance
    _logoOpacity =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0, 0.7, curve: Curves.easeOut),
    ));
    _logoScale =
        Tween<double>(begin: 0.7, end: 1).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0, 0.7, curve: Curves.easeOutBack),
    ));
    _logoRotate =
        Tween<double>(begin: -0.5, end: 0).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
    ));

    // Text reveal — 600ms delay
    _textOpacity =
        Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    ));

    _entranceCtrl.forward();

    // Float animation (continuous)
    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000));
    _floatY = Tween<double>(begin: 0, end: -5).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
    _floatCtrl.repeat(reverse: true);
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo container
          AnimatedBuilder(
            animation: Listenable.merge([_entranceCtrl, _floatCtrl]),
            builder: (_, child) {
              return Opacity(
                opacity: _logoOpacity.value.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, _floatY.value),
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Transform.rotate(
                      angle: _logoRotate.value,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF242C24), Color(0xFF1A211A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.1),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.primary,
                size: 40,
                shadows: [
                  Shadow(
                    color: AppColors.primary.withOpacity(0.4),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Greeting text
          AnimatedBuilder(
            animation: _textOpacity,
            builder: (_, child) => Opacity(
              opacity: _textOpacity.value.clamp(0.0, 1.0),
              child: child,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                widget.greeting,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MESSAGE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// User message — bubble kanan seperti HTML `.user-msg`
class _UserMessage extends StatelessWidget {
  final String content;
  const _UserMessage({required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24, left: 48),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF242C24), // var(--surface-container-high) dari HTML
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)), // var(--glass-border)
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            content,
            style: const TextStyle(
              color: Color(0xFFDDE5D9), // var(--on-surface)
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// AI message — seamless text tanpa bubble seperti HTML `.ai-msg`
class _AIMessage extends ConsumerWidget {
  final AIChatMessage message;
  const _AIMessage({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Teks AI — tanpa bubble, seamless dengan rendering Markdown
          MarkdownBody(
            data: message.content,
            styleSheet: MarkdownStyleSheet(
              p: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 15,
                height: 1.6,
              ),
              strong: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
              listBullet: const TextStyle(
                color: AppColors.primary,
                fontSize: 15,
              ),
            ),
          ),

          // Recommended songs jika ada
          if (message.recommendedSongs != null &&
              message.recommendedSongs!.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            ...message.recommendedSongs!.map((song) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SongArtworkWidget(song: song, size: 40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              song.title,
                              style: const TextStyle(
                                color: AppColors.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              song.artist,
                              style: const TextStyle(
                                color: AppColors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => ref
                            .read(playerProvider.notifier)
                            .playSong(song, message.recommendedSongs!),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withOpacity(0.15),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: AppColors.primary, size: 18),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATUS INDICATOR — thinking / loading state seperti HTML `.status-text`
// ─────────────────────────────────────────────────────────────────────────────

class _StatusIndicator extends StatefulWidget {
  final String text;
  final IconData icon;
  const _StatusIndicator({required this.text, required this.icon});

  @override
  State<_StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<_StatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
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
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          RotationTransition(
            turns: _ctrl,
            child: Icon(widget.icon, color: AppColors.primary, size: 16),
          ),
          const SizedBox(width: 8),
          Text(
            widget.text,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DOWNLOAD RICH CARD — artwork + progress bar + detail + Retry button
// Menggantikan _DownloadSystemBubble dengan desain seperti HTML `.rich-card`
// ─────────────────────────────────────────────────────────────────────────────

class _DownloadRichCard extends ConsumerWidget {
  final DownloadChatMessage message;
  const _DownloadRichCard({required this.message});

  /// [F2-2 FIX] Widget placeholder cover art — ditampilkan saat coverUrl kosong atau gagal load
  Widget _buildCoverArt(String coverUrl, {double size = 140}) {
    if (coverUrl.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.network(
            coverUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildCoverPlaceholder(size: size),
            loadingBuilder: (_, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return _buildCoverPlaceholder(size: size);
            },
          ),
        ),
      );
    }
    return _buildCoverPlaceholder(size: size);
  }

  Widget _buildCoverPlaceholder({double size = 140}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1E2B1E), Color(0xFF1DB954)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.music_note_rounded, color: Colors.white70, size: size * 0.4),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = message.progress;
    final pct = progress?.percent ?? 0.0;
    final status = progress?.status ?? DownloadStatus.idle;
    final hasActiveTrack = (progress?.currentTitle.isNotEmpty == true) ||
        (progress?.coverUrl.isNotEmpty == true);
    final isSearching = message.isProgress &&
        !hasActiveTrack &&
        (status == DownloadStatus.idle ||
            status == DownloadStatus.fetchingMetadata);
    final isError = message.content.contains('Unduhan gagal') ||
        message.content.contains('gagal') ||
        status == DownloadStatus.error;
    final isSuccess = message.content.contains('selesai') ||
        message.content.contains('sudah ada') ||
        status == DownloadStatus.done ||
        status == DownloadStatus.skipped;

    // Deteksi tipe unduhan untuk label status
    final isPlaylist = message.content.contains('playlist') ||
        message.content.contains('Playlist');

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Jika pesan sedang diproses — tampilkan status indicator
          if (isSearching) ...[
            _StatusIndicator(
              text: isPlaylist
                  ? 'Membaca playlist Spotify...'
                  : 'Menganalisis tautan & metadata...',
              icon: Icons.rotate_right_rounded,
            ),
          ],

          // Tampil pesan teks hanya jika BUKAN progress aktif
          if (!message.isProgress) ...[
            _RichDownloadText(text: message.content),
          ],

          // Rich card premium untuk progress aktif (Cover Art DI ATAS Judul)
          if (message.isProgress && !isSearching) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xDD141B14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // COVER ART DI ATAS JUDUL (CDN Spotify)
                  _buildCoverArt(progress?.coverUrl ?? '', size: 140),

                  const SizedBox(height: 16),

                  // Track Title (Di bawah Cover Art)
                  if (progress?.currentTitle.isNotEmpty == true) ...[
                    Text(
                      progress!.currentTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                  ],

                  // Artist Name
                  if (progress?.currentArtist.isNotEmpty == true) ...[
                    Text(
                      progress!.currentArtist,
                      style: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Progress Bar & Percentage
                  if ((status == DownloadStatus.downloading || status == DownloadStatus.fetchingMetadata) && pct >= 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status == DownloadStatus.fetchingMetadata
                                ? 'MEMPERSIAPKAN'
                                : 'MENGUNDUH',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        Text(
                          pct > 0 ? '${pct.toStringAsFixed(1)}%' : '0.0%',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Glowing progress bar
                    Container(
                      height: 8,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (pct / 100.0).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1DB954), Color(0xFF1ED760)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1DB954).withOpacity(0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Sub-info row (Speed, Song count, Sisa Waktu)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          progress?.speedStr.isNotEmpty == true
                              ? '↓ ${progress!.speedStr}'
                              : (status == DownloadStatus.fetchingMetadata ? 'Menyiapkan unduhan...' : ''),
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (progress?.totalSongs != null && progress!.totalSongs > 1)
                          Text(
                            'Lagu ${progress.currentSongIndex}/${progress.totalSongs}',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          progress?.etaDisplay.isNotEmpty == true
                              ? 'Sisa Waktu: ${progress!.etaDisplay}'
                              : '',
                          style: const TextStyle(
                            color: AppColors.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Converting/Tagging State
                  if (status == DownloadStatus.converting ||
                      status == DownloadStatus.tagging) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status == DownloadStatus.converting
                              ? 'Memproses Format Audio...'
                              : 'Menulis Metadata & Cover Art...',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],

          // Success action — tombol Putar
          if (isSuccess && !message.isProgress) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _CardActionButton(
                  label: 'Lihat Library',
                  icon: Icons.library_music_rounded,
                  isPrimary: true,
                  onTap: () {},
                ),
              ],
            ),
          ],

          // Error action — tombol Retry
          if (isError && !message.isProgress) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _CardActionButton(
                  label: 'Coba Lagi',
                  icon: Icons.refresh_rounded,
                  isPrimary: true,
                  onTap: () =>
                      ref.read(downloadProvider.notifier).retryLastDownload(),
                ),
                const SizedBox(width: 8),
                _CardActionButton(
                  label: 'Log Debug',
                  icon: Icons.bug_report_rounded,
                  isPrimary: false,
                  onTap: () => _showDebugLogsSheet(context),
                ),
              ],
            ),
          ],

          // Debug button selalu tersedia saat progress aktif
          if (message.isProgress) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showDebugLogsSheet(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bug_report_rounded,
                        size: 13, color: AppColors.primary),
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
        ],
      ),
    );
  }
}

class _CardActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _CardActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_CardActionButton> createState() => _CardActionButtonState();
}

class _CardActionButtonState extends State<_CardActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.95,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9999),
            color: widget.isPrimary
                ? AppColors.primary
                : Colors.white.withOpacity(0.1),
            border: widget.isPrimary
                ? null
                : Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.isPrimary
                    ? const Color(0xFF003914)
                    : AppColors.onSurface,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.isPrimary
                      ? const Color(0xFF003914)
                      : AppColors.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ANIMATED ENTRY — fade + slide up for every new message
// ─────────────────────────────────────────────────────────────────────────────

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
        vsync: this, duration: const Duration(milliseconds: 400));
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

// ─────────────────────────────────────────────────────────────────────────────
// PLAYLIST CARD
// ─────────────────────────────────────────────────────────────────────────────

class _PlaylistCard extends ConsumerWidget {
  final List<SongModel> songs;
  final String playlistName;
  final VoidCallback onTap;

  const _PlaylistCard({
    required this.songs,
    required this.playlistName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.25),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Artwork strip
            SizedBox(
              height: 72,
              child: Row(
                children: [
                  ...songs.take(5).map(
                        (s) => Expanded(
                          child: ClipRect(
                            child: SizedBox(
                              width: double.infinity,
                              height: 72,
                              child: SongArtworkWidget(
                                song: s,
                                size: 72,
                                borderRadius: 0,
                              ),
                            ),
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

            // Info + action
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
                      onPressed: () =>
                          ref.read(aiChatProvider.notifier).createPlaylistFromPending(),
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
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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

// ─────────────────────────────────────────────────────────────────────────────
// SUGGESTION BAR — chip-chip mood (dipertahankan, fungsional)
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionBar extends StatelessWidget {
  final ValueChanged<String> onTap;
  const _SuggestionBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final chips = [
      (Icons.download_rounded, 'Download Music', '__download__'),
      (Icons.code_rounded, 'Stres ngoding', 'Stres ngoding'),
      (Icons.menu_book_rounded, 'Semangat belajar', 'Semangat belajar'),
      (Icons.weekend_rounded, 'Santai weekend', 'Santai weekend'),
      (Icons.water_drop_rounded, 'Hujan melamun', 'Hujan melamun'),
      (Icons.heart_broken_rounded, 'Lagi galau', 'Lagi galau'),
      (Icons.local_fire_department_rounded, 'Hype banget', 'Hype banget'),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: chips.map((c) {
            final isDownload = c.$3 == '__download__';
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SuggestionChip(
                icon: c.$1,
                label: c.$2,
                isDownload: isDownload,
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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 100),
        lowerBound: 0.93,
        upperBound: 1.0,
        value: 1.0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _ctrl,
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

// ─────────────────────────────────────────────────────────────────────────────
// FLUID INPUT BAR — pill-shaped, fixed bottom seperti HTML `.input-area`
// ─────────────────────────────────────────────────────────────────────────────

class _FluidInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool isLoading;
  final bool isDownloading;
  final VoidCallback onSend;
  final VoidCallback? onCancelDownload;
  final String hintText;

  const _FluidInputBar({
    required this.controller,
    required this.isLoading,
    this.isDownloading = false,
    required this.onSend,
    this.onCancelDownload,
    this.hintText = 'Tanya sesuatu atau paste link Spotify...',
  });

  @override
  State<_FluidInputBar> createState() => _FluidInputBarState();
}

class _FluidInputBarState extends State<_FluidInputBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _btnAnim;
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
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.background,
            AppColors.background,
            AppColors.background.withOpacity(0),
          ],
          stops: const [0, 0.6, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Input field
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    style: const TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 15,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.isDownloading
                          ? 'Mengunduh lagu... Ketuk X untuk membatalkan'
                          : widget.hintText,
                      hintStyle: const TextStyle(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.only(
                          left: 20, right: 8, top: 14, bottom: 14),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) {
                      if (!widget.isLoading && _hasText) widget.onSend();
                    },
                    enabled: !widget.isLoading,
                  ),
                ),

                // Send / Cancel button [REQ-1.3]
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: ScaleTransition(
                    scale: _btnAnim,
                    child: GestureDetector(
                      onTapDown: (!widget.isDownloading && (widget.isLoading || !_hasText))
                          ? null
                          : (_) => _btnAnim.reverse(),
                      onTapUp: (!widget.isDownloading && (widget.isLoading || !_hasText))
                          ? null
                          : (_) {
                              _btnAnim.forward();
                              if (widget.isDownloading) {
                                widget.onCancelDownload?.call();
                              } else {
                                widget.onSend();
                              }
                            },
                      onTapCancel: () => _btnAnim.forward(),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isDownloading
                              ? const Color(0xFFE53935)
                              : ((widget.isLoading || !_hasText)
                                  ? AppColors.surfaceContainerHighest
                                  : AppColors.primary),
                        ),
                        child: widget.isDownloading
                            ? const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 22,
                              )
                            : (widget.isLoading
                                ? const Padding(
                                    padding: EdgeInsets.all(11),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: AppColors.primary,
                                    ),
                                  )
                                : Icon(
                                    Icons.arrow_upward_rounded,
                                    color: _hasText
                                        ? const Color(0xFF003914)
                                        : AppColors.onSurfaceVariant,
                                    size: 20,
                                  )),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RICH DOWNLOAD TEXT — render **bold** markers
// ─────────────────────────────────────────────────────────────────────────────

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
            fontSize: 15,
            height: 1.6,
          ),
        ));
      }
      spans.add(TextSpan(
        text: match.group(1),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          height: 1.6,
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
          fontSize: 15,
          height: 1.6,
        ),
      ));
    }

    return RichText(text: TextSpan(children: spans));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEBUG LOGS SHEET
// ─────────────────────────────────────────────────────────────────────────────

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
    setState(() => _isLoading = true);
    final logs = await DownloadService.instance.getDownloadLog();
    if (mounted) {
      setState(() {
        _logText = logs;
        _isLoading = false;
      });
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Detail log proses download & error yt-dlp',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isLoading ? null : _loadLogs,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
                IconButton(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy_all_rounded,
                      color: AppColors.primary),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF070707),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary))
                  : SingleChildScrollView(
                      controller: _scrollCtrl,
                      child: SelectionArea(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            _logText.isEmpty
                                ? 'Belum ada log yang tercatat.'
                                : _logText,
                            style: TextStyle(
                              color: _logText.contains('[ERROR]')
                                  ? Colors.red[300]
                                  : Colors.green[300],
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
