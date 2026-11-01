class AppConstants {
  // Gemini
  static const String geminiModel = 'gemini-3.5-flash-lite';
  static const String geminiFallbackModel = 'gemini-3.5-flash';
  static const String geminiBaseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  // OpenRouter (Failover — adopted from exam/js/api.js)
  static const String openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const String openRouterKey = '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';
  static const List<String> openRouterModels = [
    'google/gemma-4-31b-it:free',
    'nvidia/nemotron-3.5-lightning:free',
    'liquid/lfm-2.5-2.6b:free',
    'google/gemma-4-26b-a4b-it:free',
    'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning:free',
  ];

  // Hive boxes
  static const String songsBox = 'songs_box';
  static const String playlistsBox = 'playlists_box';
  static const String recentlyPlayedBox = 'recently_played_box';
  static const String settingsBox = 'settings_box';
  static const String lyricsCacheBox = 'lyrics_cache_box';

  // Settings keys
  static const String likedSongIdsKey = 'liked_song_ids';
  static const String repeatModeKey = 'repeat_mode';
  static const String shuffleModeKey = 'shuffle_mode';

  // Audio service
  static const String audioServiceId = 'com.ibnutify.ibnutify.audio';

  // UI
  static const double miniPlayerHeight = 64.0;
  static const double bottomNavHeight = 72.0;
  static const double borderRadius = 12.0;
  static const double cardBorderRadius = 8.0;
}
