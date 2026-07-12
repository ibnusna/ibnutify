import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ibnutify.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE songs ADD COLUMN bpm REAL');
            await db.execute('ALTER TABLE songs ADD COLUMN brightness REAL');
            await db.execute('ALTER TABLE songs ADD COLUMN percussiveness REAL');
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute('ALTER TABLE songs ADD COLUMN youtube_url TEXT');
          } catch (_) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute('ALTER TABLE songs ADD COLUMN skip_count INTEGER DEFAULT 0');
            await db.execute('ALTER TABLE songs ADD COLUMN completion_count INTEGER DEFAULT 0');
            
            await db.execute('''
              CREATE TABLE listening_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                song_id INTEGER NOT NULL,
                timestamp INTEGER NOT NULL,
                duration_listened INTEGER,
                FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
              )
            ''');
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabel Songs
    await db.execute('''
      CREATE TABLE songs (
        id INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT,
        duration INTEGER,
        uri TEXT UNIQUE NOT NULL,
        albumArtPath TEXT,
        playCount INTEGER DEFAULT 0,
        lastPlayedAt INTEGER,
        addedAt INTEGER NOT NULL,
        isLiked INTEGER DEFAULT 0,
        listenThroughCount INTEGER DEFAULT 0,
        release_year INTEGER,
        cluster_id INTEGER,
        score INTEGER DEFAULT 0,
        bpm REAL,
        brightness REAL,
        percussiveness REAL,
        youtube_url TEXT,
        skip_count INTEGER DEFAULT 0,
        completion_count INTEGER DEFAULT 0
      )
    ''');

    // Tabel Listening History
    await db.execute('''
      CREATE TABLE listening_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        duration_listened INTEGER,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    // Tabel Play Logs
    await db.execute('''
      CREATE TABLE play_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        song_id INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        duration_played INTEGER NOT NULL,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE
      )
    ''');

    // Tabel Playlists
    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        isCustom INTEGER DEFAULT 1,
        createdAt INTEGER NOT NULL
      )
    ''');

    // Tabel Playlist Songs (Many-to-Many)
    await db.execute('''
      CREATE TABLE playlist_songs (
        playlist_id TEXT NOT NULL,
        song_id INTEGER NOT NULL,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (song_id) REFERENCES songs (id) ON DELETE CASCADE,
        PRIMARY KEY (playlist_id, song_id)
      )
    ''');

    // Tabel Lyrics Cache
    await db.execute('''
      CREATE TABLE lyrics_cache (
        songId INTEGER PRIMARY KEY,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        lyrics TEXT NOT NULL,
        source TEXT NOT NULL,
        createdAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> clearAll() async {
    final db = await instance.database;
    await db.delete('songs');
    await db.delete('play_logs');
    await db.delete('listening_history');
    await db.delete('playlists');
    await db.delete('playlist_songs');
  }
}
