# Graph Report - .  (2026-07-24)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 1214 nodes · 1805 edges · 68 communities (63 shown, 5 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.8)
- Token cost: 3,228 input · 767 output

## Graph Freshness
- Built from commit: `b34f9b83`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- AI Chat Providers
- Search and Navigation State
- Library and Playlist Management
- Album Art Notifier
- Download Service
- AI Moods UI Components
- Audio Handler and Playback
- Song and Playback Models
- iOS App Delegate
- Database and Cache Helpers
- Local Music Data Source
- Music Repository
- Python Downloader Backend
- Gemini AI Integration
- Album Art Service
- Video Player Controller
- Home Screen UI Components
- Linux Platform Integration
- Player Screen UI
- App Constants and Config
- Online Artwork Service
- Song and Queue Widgets
- App Theme and Colors
- Player State Notifier
- Local Lyrics Service
- Win32 Window Management
- Song Artwork Widget
- Spotify Downloader App
- Playlist State Notifier
- Windows Flutter Window
- Custom UI Animations
- Playlist Selection Screen
- AI Chat and Sync
- Lyrics API Service
- Win32 Window Properties
- App Entry Point
- Search Screen UI
- Mini Player Animation
- Song List Components
- Windows C++ Utilities
- Metadata Extraction Service
- Playlist Data Model
- Web App Manifest
- Lyrics API Testing
- Smart Shuffle Service
- Lyrics Cache Model
- Main Shell Navigation
- Auto Lyrics Downloader
- Windows Message Handling
- Machine Learning Service
- Connectivity Provider
- State Notifiers
- Android Activity Configuration
- LRC Lyrics Parser
- Formatting Utilities
- Online Art Provider
- Music Feature Analyzer
- AI Chat Actions
- Audio Handler Interfaces
- Windows Plugin Registry
- Flutter Widget Tests
- Nullable String Type

## God Nodes (most connected - your core abstractions)
1. `playerProvider` - 34 edges
2. `songsProvider` - 24 edges
3. `musicRepositoryProvider` - 23 edges
4. `Win32Window` - 22 edges
5. `SpotifyDownloaderApp` - 16 edges
6. `playlistsProvider` - 15 edges
7. `audioHandlerProvider` - 14 edges
8. `_LibraryScreenState` - 13 edges
9. `MessageHandler` - 12 edges
10. `download_track()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `_loadArtwork` --references--> `musicRepositoryProvider`  [EXTRACTED]
  lib/presentation/widgets/common/song_artwork_widget.dart → lib/presentation/providers/app_providers.dart
- `build` --references--> `playerProvider`  [EXTRACTED]
  lib/presentation/screens/queue/queue_screen.dart → lib/presentation/providers/app_providers.dart
- `build` --references--> `playerProvider`  [EXTRACTED]
  lib/presentation/widgets/common/song_list_tile.dart → lib/presentation/providers/app_providers.dart
- `build` --references--> `playerProvider`  [EXTRACTED]
  lib/presentation/widgets/player/mini_player.dart → lib/presentation/providers/app_providers.dart
- `OnCreate` --calls--> `RegisterPlugins()`  [INFERRED]
  windows/runner/flutter_window.h → windows/flutter/generated_plugin_registrant.cc

## Import Cycles
- None detected.

## Communities (68 total, 5 thin omitted)

### Community 0 - "AI Chat Providers"
Cohesion: 0.03
Nodes (62): aiMoodsProvider, apiKey, awaitingUrl, buildContextualQueue, _buildProgressText, clear, clearChat, clearMessages (+54 more)

### Community 1 - "Search and Navigation State"
Cohesion: 0.05
Nodes (60): ConsumerState, ConsumerStatefulWidget, albumArtProvider, isVideoModeProvider, navigationProvider, searchQueryProvider, searchResultsProvider, selectedGenreProvider (+52 more)

### Community 2 - "Library and Playlist Management"
Cohesion: 0.05
Nodes (56): createPlaylistFromPending, dailyMixesProvider, duplicateSongsProvider, mlProgressProvider, playlistsProvider, recentlyPlayedProvider, songErasProvider, topSongsProvider (+48 more)

### Community 3 - "Album Art Notifier"
Cohesion: 0.05
Nodes (47): app_providers.dart, bool get, ConsumerWidget, AlbumArtNotifier, AlbumArtState, artBytes, artUri, build (+39 more)

### Community 4 - "Download Service"
Cohesion: 0.04
Nodes (44): album, artist, _channel, coverUrl, currentArtist, currentSongIndex, currentTitle, downloadPlaylist (+36 more)

### Community 5 - "AI Moods UI Components"
Cohesion: 0.05
Nodes (41): Animation, ../../../data/datasources/gemini_datasource.dart, DownloadChatMessage, _barCount, _btnAnim, _btnScale, child, _controller (+33 more)

### Community 6 - "Audio Handler and Playback"
Cohesion: 0.05
Nodes (40): AudioPlayer, AudioPlayer get, class IbnuTifyAudioHandler extends, ConcatenatingAudioSource?, addNextToQueue, _artworksCache, _audioSource, _broadcastState (+32 more)

### Community 7 - "Song and Playback Models"
Cohesion: 0.06
Nodes (33): double?, int?, durationPlayed, fromMap, id, PlayLogEntry, songId, timestamp (+25 more)

### Community 8 - "iOS App Delegate"
Cohesion: 0.07
Nodes (22): Any, Cocoa, Flutter, FlutterAppDelegate, FlutterMacOS, FlutterPluginRegistry, FlutterViewController, Foundation (+14 more)

### Community 9 - "Database and Cache Helpers"
Cohesion: 0.06
Nodes (31): clearAll, _createDB, _database, DatabaseHelper, _initDB, instance, evict, hasCache (+23 more)

### Community 10 - "Local Music Data Source"
Cohesion: 0.06
Nodes (31): Future, addSongsToPlaylist, addSongToPlaylist, async, _audioQuery, _channel, createPlaylist, deletePlaylist (+23 more)

### Community 11 - "Music Repository"
Cohesion: 0.06
Nodes (30): MusicLocalDatasource, addSongsToPlaylist, addSongToPlaylist, analyzeLibraryMoods, createPlaylist, deletePlaylist, deleteSong, _gemini (+22 more)

### Community 12 - "Python Downloader Backend"
Cohesion: 0.13
Nodes (25): _add_debug_log(), _add_generic_metadata(), _add_mp3_metadata(), download_playlist(), download_track(), get_download_log(), get_download_progress(), _get_itunes_metadata() (+17 more)

### Community 13 - "Gemini AI Integration"
Cohesion: 0.07
Nodes (29): ../../core/constants/app_constants.dart, AIChatMessage, _AIChatResponse, AIMood, analyzeLibraryMoods, apiKey, artist, _buildMessage (+21 more)

### Community 14 - "Album Art Service"
Cohesion: 0.07
Nodes (26): ../data/datasources/music_local_datasource.dart, AlbumArtResult, AlbumArtService, artBytes, artUri, _bytesCache, _clampToDark, _colorCache (+18 more)

### Community 15 - "Video Player Controller"
Cohesion: 0.08
Nodes (24): DateTime, _controller, createState, didUpdateWidget, dispose, _errorMessage, initState, _initVideo (+16 more)

### Community 16 - "Home Screen UI Components"
Cohesion: 0.10
Nodes (24): ../../../core/utils/format_utils.dart, NamedPlaylist, _DownloadSystemBubble, _M3TopBar, _PlaylistCard, _RichDownloadText, _SuggestionBar, allSongs (+16 more)

### Community 17 - "Linux Platform Integration"
Cohesion: 0.10
Nodes (20): FlPluginRegistry, GApplication, gboolean, gchar, GObject, GtkApplication, fl_register_plugins(), main() (+12 more)

### Community 18 - "Player Screen UI"
Cohesion: 0.09
Nodes (22): _adaptiveFontSize, _animateToGradient, _artController, _buildEmptyState, _buildLoadingState, _buildLyricsPreview, createState, dispose (+14 more)

### Community 19 - "App Constants and Config"
Cohesion: 0.09
Nodes (21): AppConstants, audioServiceId, borderRadius, bottomNavHeight, cardBorderRadius, geminiBaseUrl, geminiModel, likedSongIdsKey (+13 more)

### Community 20 - "Online Artwork Service"
Cohesion: 0.10
Nodes (19): _cacheDir, _cacheDirectory, _fetchAlbumUrl, _fetchAndCache, _fetchArtistUrl, _fetchArtistViaAlbumSearch, getAlbumCoverPath, getArtistImagePath (+11 more)

### Community 21 - "Song and Queue Widgets"
Cohesion: 0.12
Nodes (17): ../common/song_artwork_widget.dart, core/theme/app_theme.dart, IconData, SongModel, build, onTap, _QueueTile, song (+9 more)

### Community 22 - "App Theme and Colors"
Cohesion: 0.11
Nodes (18): AppColors, AppTheme, background, emerald, emeraldDark, error, onBackground, onSurface (+10 more)

### Community 23 - "Player State Notifier"
Cohesion: 0.12
Nodes (19): _onSongChanged, addToQueue, audioHandlerProvider, clearQueue, cycleRepeat, _fetchAndSendArtwork, musicLocalDatasourceProvider, nextTrack (+11 more)

### Community 24 - "Local Lyrics Service"
Cohesion: 0.11
Nodes (17): _bigEndianInt, _cache, _cleanLyrics, clearCache, _decodeUslt, _decodeUtf16, evict, _extractLyricsFromFile (+9 more)

### Community 25 - "Win32 Window Management"
Cohesion: 0.18
Nodes (14): Point, Size, wchar_t, Scale(), Create, Destroy, UpdateTheme, Win32Window::Win32Window() (+6 more)

### Community 26 - "Song Artwork Widget"
Cohesion: 0.12
Nodes (16): BoxFit, _artworkBytes, borderRadius, build, createState, didUpdateWidget, fit, initState (+8 more)

### Community 28 - "Playlist State Notifier"
Cohesion: 0.16
Nodes (16): AsyncNotifier, addSong, addSongs, analyze, build, delete, deleteSong, mlServiceProvider (+8 more)

### Community 29 - "Windows Flutter Window"
Cohesion: 0.13
Nodes (13): unique_ptr, DartProject, HWND, LPARAM, LRESULT, UINT, WPARAM, FlutterWindow (+5 more)

### Community 30 - "Custom UI Animations"
Cohesion: 0.22
Nodes (15): _AnimatedEntry, _AnimatedEntryState, _DebugLogsSheet, _DebugLogsSheetState, _M3InputBar, _M3InputBarState, _MusicEqualizerAnimation, _MusicEqualizerAnimationState (+7 more)

### Community 31 - "Playlist Selection Screen"
Cohesion: 0.14
Nodes (13): class, _confirm, createState, dispose, existingSongIds, _filteredSongs, initState, playlistId (+5 more)

### Community 32 - "AI Chat and Sync"
Cohesion: 0.15
Nodes (14): addToLikedSongs, AIChatNotifier, AIChatState, geminiDatasourceProvider, _handlePlaylistDownload, handleUserInput, playFromSearch, sendMessage (+6 more)

### Community 33 - "Lyrics API Service"
Cohesion: 0.14
Nodes (13): _baseUrl, _cleanApiLyrics, fetchLyrics, fetchWithFallback, instance, LyricsApiService, _sanitize, _stripLrcTimestamps (+5 more)

### Community 34 - "Win32 Window Properties"
Cohesion: 0.20
Nodes (14): RECT, OnCreate, OnDestroy, HWND, Win32Window, child_content_, GetClientArea, OnCreate (+6 more)

### Community 35 - "App Entry Point"
Cohesion: 0.15
Nodes (12): build, IbnuTifyApp, main, widgetsBinding, package:audio_service/audio_service.dart, package:flutter_dotenv/flutter_dotenv.dart, package:flutter/material.dart, package:flutter_native_splash/flutter_native_splash.dart (+4 more)

### Community 36 - "Search Screen UI"
Cohesion: 0.15
Nodes (12): _controller, createState, dispose, genre, _GenreCard, _genres, _isSearching, onTap (+4 more)

### Community 37 - "Mini Player Animation"
Cohesion: 0.17
Nodes (11): AnimationController, Color, _animateTo, build, _controller, createState, dispose, _fromColor (+3 more)

### Community 38 - "Song List Components"
Cohesion: 0.17
Nodes (11): ../../data/models/song_model.dart, build, _formatDuration, onTap, queue, showDuration, song, trailing (+3 more)

### Community 39 - "Windows C++ Utilities"
Cohesion: 0.24
Nodes (9): _In_, _In_opt_, vector, wWinMain(), string, wchar_t, CreateAndAttachConsole(), GetCommandLineArguments() (+1 more)

### Community 40 - "Metadata Extraction Service"
Cohesion: 0.18
Nodes (10): dart:typed_data, _bigEndianInt, _decodeWxxx, extractYoutubeUrl, instance, MetadataService, _parseWxxx, _syncsafeInt (+2 more)

### Community 41 - "Playlist Data Model"
Cohesion: 0.18
Nodes (10): copyWith, createdAt, description, fromMap, id, isCustom, name, PlaylistModel (+2 more)

### Community 42 - "Web App Manifest"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 43 - "Lyrics API Testing"
Cohesion: 0.22
Nodes (8): dart:convert, dart:io, client, main, uri, client, main, uri

### Community 44 - "Smart Shuffle Service"
Cohesion: 0.20
Nodes (9): dart:math, computeSmartShuffleIndices, currentSongId, queue, recentSongIds, SmartShuffleArgs, SmartShuffleService, _smartShuffleTask (+1 more)

### Community 45 - "Lyrics Cache Model"
Cohesion: 0.20
Nodes (9): artist, createdAt, fromMap, lyrics, LyricsCacheModel, songId, source, title (+1 more)

### Community 46 - "Main Shell Navigation"
Cohesion: 0.20
Nodes (9): createState, package:ibnutify/services/auto_lyrics_downloader.dart, ../providers/album_art_provider.dart, ../providers/app_providers.dart, ../screens/ai_moods/ai_moods_screen.dart, ../screens/home/home_screen.dart, ../screens/library/library_screen.dart, ../screens/search/search_screen.dart (+1 more)

### Community 47 - "Auto Lyrics Downloader"
Cohesion: 0.20
Nodes (9): AutoLyricsDownloader, instance, _isRunning, start, stop, package:flutter/foundation.dart, package:ibnutify/data/datasources/music_local_datasource.dart, package:ibnutify/data/repositories/lyrics_repository.dart (+1 more)

### Community 48 - "Windows Message Handling"
Cohesion: 0.36
Nodes (10): HWND, LPARAM, LRESULT, UINT, WPARAM, EnableFullDpiSupportIfAvailable(), GetHandle, GetThisFromHandle (+2 more)

### Community 49 - "Machine Learning Service"
Cohesion: 0.22
Nodes (8): MusicRepository, _channel, MLService, processAndClusterSongs, _repository, package:flutter/services.dart, package:ibnutify/data/repositories/music_repository.dart, static const

### Community 50 - "Connectivity Provider"
Cohesion: 0.25
Nodes (7): dart:async, _checkInternet, ConnectivityNotifier, dispose, _timer, StateNotifier, Timer?

### Community 51 - "State Notifiers"
Cohesion: 0.25
Nodes (8): AIMoodsNotifier, AIMoodsState, AppScreen, DownloadNotifier, DownloadState, NavigationNotifier, SearchNotifier, Notifier

### Community 52 - "Android Activity Configuration"
Cohesion: 0.33
Nodes (4): MainActivity, Context, FlutterActivity, FlutterEngine

### Community 53 - "LRC Lyrics Parser"
Cohesion: 0.29
Nodes (6): Duration, LrcLine, LrcParser, parse, text, timestamp

### Community 54 - "Formatting Utilities"
Cohesion: 0.29
Nodes (6): formatDuration, formatDurationSeconds, getGreeting, hour, minutes, seconds

### Community 55 - "Online Art Provider"
Cohesion: 0.33
Nodes (5): album, artist, sep, package:flutter_riverpod/flutter_riverpod.dart, ../../services/online_art_service.dart

### Community 57 - "AI Chat Actions"
Cohesion: 0.67
Nodes (4): aiChatProvider, downloadProvider, build, _sendMessage

### Community 58 - "Audio Handler Interfaces"
Cohesion: 0.50
Nodes (4): BaseAudioHandler, IbnuTifyAudioHandler, QueueHandler, SeekHandler

## Knowledge Gaps
- **634 isolated node(s):** `AppConstants`, `geminiModel`, `geminiBaseUrl`, `openRouterUrl`, `openRouterKey` (+629 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **5 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `SongModel` connect `Song and Queue Widgets` to `AI Chat Providers`, `Library and Playlist Management`, `Song List Components`, `Song and Playback Models`, `Home Screen UI Components`, `Song Artwork Widget`, `Playlist Selection Screen`?**
  _High betweenness centrality (0.022) - this node is a cross-community bridge._
- **Why does `playerProvider` connect `Album Art Notifier` to `AI Chat Providers`, `Search and Navigation State`, `Library and Playlist Management`, `Mini Player Animation`, `Song List Components`, `Video Player Controller`, `Song and Queue Widgets`, `AI Chat Actions`, `Playlist State Notifier`?**
  _High betweenness centrality (0.021) - this node is a cross-community bridge._
- **Why does `MusicLocalDatasource` connect `Music Repository` to `AI Chat Providers`, `Local Music Data Source`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **What connects `AppConstants`, `geminiModel`, `geminiBaseUrl` to the rest of the system?**
  _634 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `AI Chat Providers` be split into smaller, more focused modules?**
  _Cohesion score 0.031746031746031744 - nodes in this community are weakly interconnected._
- **Should `Search and Navigation State` be split into smaller, more focused modules?**
  _Cohesion score 0.05027322404371585 - nodes in this community are weakly interconnected._
- **Should `Library and Playlist Management` be split into smaller, more focused modules?**
  _Cohesion score 0.05263157894736842 - nodes in this community are weakly interconnected._