# IbnuTify - Enterprise Technical Documentation

## 1. Executive Summary
IbnuTify is a next-generation offline-first music streaming application built with Flutter. It mimics the core functionalities of premium platforms like Spotify while providing advanced on-device Machine Learning capabilities. IbnuTify automatically scans local storage, extracts audio features (BPM, brightness, percussiveness) using Python (Chaquopy), and utilizes K-Means clustering to generate intelligent "Daily Mixes" and "Era Mixes" entirely offline.

## 2. Product Overview
IbnuTify provides users with a seamless, ad-free, local music listening experience. It features a modern, fluid UI (Material 3), background audio playback, media notification controls, and AI-driven dynamic playlists. 

## 3. Business Objectives
- Provide a robust offline alternative to mainstream music streaming services.
- Leverage on-device AI to curate personalized playlists without relying on cloud servers or internet connectivity.
- Ensure maximum user retention through a premium, responsive, and intuitive UI/UX.

## 4. System Overview
The system is a standalone mobile application (Android-first). It consists of a Flutter frontend, a Dart-based SQLite local database, a native audio playback engine (`just_audio` + `audio_service`), and an embedded Python ML engine (`Chaquopy`).

## 5. Technology Stack
- **Frontend Framework:** Flutter (Dart)
- **State Management:** Riverpod (`flutter_riverpod`)
- **Local Database:** SQLite (`sqflite`)
- **Audio Engine:** `just_audio`, `audio_service`, `just_audio_background`
- **Machine Learning Engine:** Chaquopy (Embedded Python 3.10)
- **Permissions & Storage:** `permission_handler`, `on_audio_query` (or native MediaStore queries)
- **Sensor Fusion:** `sensors_plus` (Accelerometer & Gyroscope)
- **Smartwatch BLE Integration:** `flutter_blue_plus` (BLE GATT Central for Heart Rate Service)
- **Target Platform:** Android (ARM64 optimized)

## 6. Architecture Overview
IbnuTify implements a **Clean Architecture** combined with **MVVM (Model-View-ViewModel)** principles. 
- **View Layer:** Flutter UI components (`screens`, `widgets`).
- **ViewModel Layer:** Riverpod Notifiers (`SongsNotifier`, `PlayerNotifier`).
- **Service Layer:** Audio handler, ML service, Database helper.
- **Repository Layer:** Abstracts data sources (SQLite, MediaStore).
- **Data Source Layer:** Direct API/DB interactions.

## 7. Application Structure
```text
lib/
├── core/           # Theme, constants, utils
├── data/           # Models, repositories, local database
├── presentation/   # Screens, widgets, providers (MVVM)
├── services/       # AudioHandler, MLService
└── main.dart       # App entry point
```

## 8. Module Breakdown
- **Core Module:** Application theme (AppColors, dark mode), format utilities (duration parsing).
- **Data Module:** `SongModel`, `PlaylistModel`, `MusicLocalDataSource`, `MusicRepository`.
- **Presentation Module:** Home, Search, Library, and Player screens. UI widgets (MiniPlayer, SongArtworkWidget).
- **Services Module:** 
  - `AudioHandler`: Manages `just_audio` state and background OS hooks.
  - `MLService`: Bridges Dart to Kotlin/Python via `MethodChannel`.
- **Workout Mode & Sensor Fusion Module:**
  - `WorkoutTaskHandler`: Runs in a separate Dart isolate via `flutter_foreground_task` Android Foreground Service to prevent background freezing when device is locked.
  - `SensorFusionEngine`: Orchestrates real-time inputs from GPS, Accelerometer, and Gyroscope. Combines magnitude calculations via `StepDetector` (with low-pass filtering and peak detection for cadence/SPM), `AltitudeKalmanFilter` (simple 1D Kalman filter to smooth altitude telemetry), and `ActivityClassifier` (rule-based heuristic to auto-detect Walking, Running, Cycling, or Hiking).
  - `CalorieEstimator`: Estimates energy expenditure using the Keytel Formula (using HR) or MET-based equations (fallback).
- **Smartwatch BLE Module:**
  - `WatchService`: Manages scanning for BLE peripherals, standard GATT handshake, service discovery for Heart Rate Service (`0x180D`), and subscribing to notification characteristic (`0x2A37`). Handles auto-reconnection to the last paired device via `SharedPreferences`.

## 9. Authentication System
Information not found in source code. (IbnuTify is a local-first application and does not currently implement user registration or cloud authentication).

## 10. Authorization System
Information not found in source code. (No role-based access control exists as it is a single-user local app).

## 11. User Management
Information not found in source code. User preferences are implicitly handled via local state, but no formal User Profile table exists.

## 12. Music Streaming Engine
IbnuTify acts as a local music player. It relies on the device's local file system (`URI`) rather than network streams. `just_audio` serves as the underlying engine handling decoding, buffering (for local files), and playback.

## 13. Audio Playback System
- **Engine:** `just_audio`
- **Background Support:** `audio_service` integrates with Android's MediaSession, allowing playback controls from the lock screen and notification drawer.
- **Features:** Play, Pause, Skip Next, Skip Previous, Seek, Shuffle, Repeat (All/One/Off).
- **Priority Queueing (Spotify-style):** Implemented temporary manual queueing via `addNextToQueue` in the custom audio handler. When adding individual tracks or whole playlists/albums to the queue:
  - Added items are placed immediately after the current playing song.
  - Manual queue items stack and have higher priority than the autoplaying playlist.
  - Visual shortcuts (Queue button) are integrated on Track Options, Recently Played header, On Repeat header, and Playlist/Album details.

## 14. Playlist Management
- **Smart Playlists (AI):** Daily Mixes (Senin-Minggu) are auto-generated using K-Means clustering on audio features (BPM, Brightness, Percussiveness).
- **Era Playlists:** Songs are grouped by release year extracted from ID3 tags or file modification dates.
- **User Playlists:** Users can create custom playlists and add/remove songs via the Library screen. Saved in SQLite.

## 15. Search System
Implements a real-time local search. The `SearchScreen` uses a `TextField` bound to a Riverpod provider (`searchQueryProvider`) which filters the global `songsProvider` list by Title, Artist, or Album using case-insensitive string matching.

## 16. Recommendation System
The "Made For You" (Daily Mix) section uses a custom recommendation engine:
1. Python extracts audio features via a Hash/ID fallback or `librosa` (if available).
2. K-Means clustering groups songs into 7 distinct clusters.
3. Each cluster is assigned to a day of the week, generating cohesive, mood-based playlists automatically.

## 17. Download & Offline System
All features are 100% offline by design. The app scans the device's `MediaStore` (or specific directories) to index local `.mp3` files. No network downloading is implemented.

## 18. Database Documentation
**Technology:** SQLite (`sqflite`)
**Schema Version:** 7
**Tables:**
1. `songs`:
   - `id` (INTEGER PRIMARY KEY)
   - `uri` (TEXT UNIQUE NOT NULL)
   - `title`, `artist`, `album` (TEXT)
   - `duration`, `play_count`, `added_at` (INTEGER)
   - `bpm`, `brightness`, `percussiveness` (REAL)
   - `cluster_id`, `release_year`, `skip_count`, `completion_count` (INTEGER)
   - `youtube_url` (TEXT)
2. `playlists`:
   - `id` (TEXT PRIMARY KEY)
   - `name`, `description` (TEXT)
   - `isCustom`, `created_at` (INTEGER)
3. `playlist_songs`:
   - `playlist_id` (TEXT), `song_id` (INTEGER, Composite Primary Key)
4. `listening_history`:
   - `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
   - `song_id` (INTEGER)
   - `timestamp`, `duration_listened` (INTEGER)
5. `activities`:
   - `id` (INTEGER PRIMARY KEY AUTOINCREMENT)
   - `sport_mode`, `created_at` (TEXT)
   - `duration` (INTEGER)
   - `distance` (REAL)
   - `route_points` (TEXT - JSON coordinates)
   - `step_count`, `avg_heart_rate_bpm` (INTEGER)
   - `elevation_gain_m`, `estimated_calories` (REAL)
6. `deleted_songs` (blacklist):
   - `id` (INTEGER PRIMARY KEY)
   - `uri` (TEXT)

## 19. API Documentation
Information not found in source code. No external REST/GraphQL APIs are consumed. All communication is done via internal Flutter `MethodChannel` (`com.ibnutify.ml/audio`) to communicate with native Android Kotlin and Python.

## 20. Screen Documentation
1. **HomeScreen:** Displays Greeting, Daily Mixes (AI), Song Eras, and Recently Played.
2. **SearchScreen:** Text input for filtering the local library.
3. **LibraryScreen:** Manages User Custom Playlists, Liked Songs, and displays all tracks.
4. **PlayerScreen:** Full-screen playback UI, dynamic background color based on Album Art, seek bar, and playback controls.
5. **WorkoutActiveScreen:** Full-screen workout tracker dashboard showing duration, distance, pace, real-time map, sensor fusion stats (steps, cadence, elevation gain, calories), and smartwatch heart rate zone telemetry. Includes pairing sheet triggers.
6. **WorkoutSummaryScreen:** Summary display shown after stopping a workout, presenting an 8-stat bento grid of exercise performance and path mapping before committing to DB.
7. **WorkoutHistoryScreen:** History overview displaying a card-based list of all past logged activities.
8. **WorkoutDetailScreen:** Full detail screen mapping the route path and plotting statistics for a past workout activity.

## 21. UI/UX Documentation
- **Design Language:** Modern, dark-mode focused, glassmorphism elements, Spotify-inspired layout.
- **Interactions:** Swipe-down to dismiss player, bottom navigation bar, modal bottom sheets for song options.
- **Dynamic Theming:** `albumArtProvider` extracts dominant colors from the current playing song's album art to tint the `PlayerScreen` background seamlessly.

## 22. State Management Documentation
**Library:** `flutter_riverpod`
- `songsProvider`: `AsyncNotifier` managing the entire local song library and triggering background ML sync.
- `playerProvider`: Manages current playing song, queue, playback state (playing/paused), and shuffle/repeat modes.
- `navigationProvider`: Manages BottomNavigationBar index state.
- `workoutProvider`: `Notifier` representing the active `WorkoutState` and coordinating start/pause/resume/stop hooks.
- `watchStateProvider`: `StreamProvider` emitting smartwatch BLE connection events (`WatchState`).
- `watchHrProvider`: `StreamProvider` emitting live parsed heart rate updates.
- `activitiesProvider`: `FutureProvider` loading historical logged workouts from SQLite.

## 23. Storage Documentation
- **Audio Files:** Reside on external/internal Android storage. App requires `READ_EXTERNAL_STORAGE` or `READ_MEDIA_AUDIO` permissions.
- **App Data:** SQLite database stored in the app's secure internal sandbox.
- **Cache:** Album artwork is loaded directly from ID3 tags on the fly.

## 24. Security Documentation
- **Permissions:** Requests Android runtime permissions securely.
- **Data Privacy:** 100% of data processing (including ML analysis) happens on-device. Zero data is transmitted to the cloud, ensuring total user privacy.

## 25. Performance Documentation
- **Lazy Loading:** `ListView.builder` and `Sliver` lists are used extensively to ensure 60fps scrolling even with thousands of local songs.
- **Background Processing:** Python initialization (`Python.start`) and K-Means clustering are offloaded to Kotlin background threads (`thread { ... }`) to prevent UI thread blocking (Splash Screen freeze).
- **Caching:** Audio features are stored in SQLite so analysis only runs once per new song.

## 26. Deployment Documentation
- **Build Tool:** Gradle / Flutter CLI
- **Command:** `flutter build apk --release --target-platform android-arm64`
- **Python Integration:** Chaquopy Gradle plugin automatically packages the Python environment and `analyzer.py` into the APK assets.

## 27. Third-party Integrations
- **Chaquopy:** Allows embedded Python execution on Android.
- **Just Audio:** Advanced audio playback engine.
- **Audio Service:** OS-level background playback integration.

## 28. Error Handling Strategy
- **Python ML Failsafes:** If native audio decoding (`librosa`) or ML clustering (`sklearn`) fails due to device constraints, `analyzer.py` utilizes a deterministic Hash-based fallback to guarantee the UI (Daily Mix) never crashes and always populates.
- **State Errors:** Riverpod `AsyncValue.guard` catches repository exceptions, defaulting to empty lists safely.
- **AI Chat Failover (API):** Implements a multi-tier fallback architecture (Gemini-3-flash-preview -> OpenRouter models rotation -> Static fallback). If all endpoints fail, the error details (HTTP status, exceptions) are captured and displayed directly in the chat UI as dynamic **Debug Info** for easy troubleshooting.

## 29. Logging Strategy
Standard Flutter `debugPrint` is utilized during development. Native Android crashes are caught in Kotlin `try-catch` blocks and forwarded to Dart via `result.error()`.

## 30. Monitoring Strategy
Information not found in source code. Offline application; no crashlytics or analytics tracking is present.

## 31. Testing Strategy
Manual Developer Validation required. Code heavily relies on native Android integrations (MediaStore, Chaquopy) which requires physical device testing.

## 32. Source Code Structure
Strict modular separation between `presentation` (UI), `data` (SQLite, Repositories), and `services` (ML, Audio). Native code resides in `android/app/src/main/kotlin` and `android/app/src/main/python`.

## 33. Dependency Documentation
- `flutter_riverpod`: State
- `just_audio`, `audio_service`: Audio
- `sqflite`, `path_provider`: Database
- `permission_handler`: OS Security
- `on_audio_query`: MediaStore scanning

## 34. Configuration Documentation
- `AndroidManifest.xml` configures foreground services (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `FOREGROUND_SERVICE_LOCATION`, `FOREGROUND_SERVICE_HEALTH`), required permissions (including `POST_NOTIFICATIONS` and BLE permissions), and audio service receivers.
- `build.gradle` defines target compileSdk (version 35 for foreground task requirements) and the Chaquopy Python environment (version 3.10, optimized without heavy ML libs to prevent installation timeouts).

## 35. Future Scalability Notes
- Migration to full Isolate-based background scanning in Dart.
- Potential integration of `librosa` natively in C++ for faster audio extraction without Python overhead.
- Cloud sync capabilities using Firebase/Supabase for cross-device playlist sharing.

## 36. Technical Appendix
**Method Channel Specifications:**
- Channel: `com.ibnutify.ml/audio`
- `extractFeatures`: Takes `filePath`, returns JSON `{"bpm": double, "brightness": double, "percussiveness": double, "release_year": int}`
- `clusterSongs`: Takes `featuresJson`, returns JSON array of `{"id": int, "cluster": int}`.
