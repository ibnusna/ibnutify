import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../models/song_model.dart';

// ─── AIMood (legacy — dipakai oleh AIMoodsNotifier lama) ─────────────────────

class AIMood {
  final String mood;
  final List<int> songIds;
  final String description;

  const AIMood({
    required this.mood,
    required this.songIds,
    required this.description,
  });

  factory AIMood.fromJson(Map<String, dynamic> json) {
    return AIMood(
      mood: json['mood'] as String,
      songIds: (json['songIds'] as List).cast<int>(),
      description: json['description'] as String,
    );
  }
}

// ─── AI Chat Models ───────────────────────────────────────────────────────────

enum ChatRole { user, ai }

class AIChatMessage {
  final ChatRole role;
  final String content;
  final List<SongModel>? recommendedSongs;
  final String? pendingPlaylistName;

  const AIChatMessage({
    required this.role,
    required this.content,
    this.recommendedSongs,
    this.pendingPlaylistName,
  });
}

class _RecommendedSong {
  final int id;
  final String title;
  final String artist;

  const _RecommendedSong({
    required this.id,
    required this.title,
    required this.artist,
  });
}

class _AIChatResponse {
  final String chatResponse;
  final String playlistName;
  final List<int> songIds;
  final List<_RecommendedSong> songs;

  const _AIChatResponse({
    required this.chatResponse,
    required this.playlistName,
    required this.songIds,
    required this.songs,
  });
}

// ─── GeminiDatasource ─────────────────────────────────────────────────────────

class GeminiDatasource {
  final String apiKey;

  GeminiDatasource({required this.apiKey});

  // ─── AI Chat (Failover) ──────────────────────────────────────────────────

  /// Menganalisis input mood pengguna dan mencocokkan dengan lagu lokal.
  /// Adopsi arsitektur failover dari exam/js/api.js:
  /// Tier 1: Gemini → Tier 2: OpenRouter (model rotation) → Tier 3: static fallback
  Future<AIChatMessage> sendChatMessage(
    String userInput,
    List<SongModel> localSongs,
  ) async {
    if (localSongs.isEmpty) {
      return const AIChatMessage(
        role: ChatRole.ai,
        content: 'Library musikmu masih kosong. Scan dulu lagu-lagunya ya dari tab Library!',
      );
    }

    final songListText = localSongs
        .map((s) => 'ID:${s.id}|${s.title}|${s.artist}')
        .join('\n');

    final systemPrompt =
        'Kamu adalah AI DJ personal bernama IbnuTify AI. '
        'Tugasmu adalah merekomendasikan lagu dari library lokal pengguna sesuai mood mereka. '
        'PENTING: Kamu HANYA boleh merekomendasikan lagu dari ID yang ada di daftar. '
        'JANGAN mengarang lagu yang tidak ada di daftar. '
        'Balas dengan bahasa Indonesia yang santai dan menyenangkan.';

    final userPrompt = '''
Input pengguna: "$userInput"

Daftar lagu yang tersedia di library lokal:
$songListText

TUGAS:
1. Analisis mood/kebutuhan dari input pengguna.
2. Pilih 5–15 lagu yang paling cocok HANYA dari ID yang ada di daftar di atas.
3. Buat nama playlist yang kreatif dan relevan.
4. Buat respons chat yang personal dan menarik.

Kembalikan HANYA dalam format JSON berikut (tanpa teks lain):
{
  "chatResponse": "string (teks balasan untuk ditampilkan di chat, singkat tapi personal)",
  "playlistName": "string (nama playlist kreatif)",
  "songIds": [int, int, ...],
  "songs": [
    {
      "id": int,
      "title": "string (judul lagu persis dari daftar)",
      "artist": "string (nama artis persis dari daftar)"
    }
  ]
}''';

    Exception? lastError;

    // ── Tier 1: Gemini ───────────────────────────────────────────────────────
    if (apiKey.isNotEmpty) {
      try {
        final result = await _tryGemini(systemPrompt, userPrompt);
        return _buildMessage(result, localSongs);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }

    // ── Tier 2: OpenRouter (model rotation) ─────────────────────────────────
    try {
      final result = await _tryOpenRouter(systemPrompt, userPrompt);
      return _buildMessage(result, localSongs);
    } catch (e) {
      lastError = e is Exception ? e : Exception(e.toString());
    }

    // ── Tier 3: Static fallback ──────────────────────────────────────────────
    return AIChatMessage(
      role: ChatRole.ai,
      content:
          'Maaf, server AI sedang sibuk. Coba lagi sebentar ya!\n\n'
          '**Debug Info:**\n${lastError?.toString() ?? "Unknown error"}',
    );
  }

  // ── Tier 1: Gemini implementation ─────────────────────────────────────────

  Future<_AIChatResponse> _tryGemini(String system, String user) async {
    final url = Uri.parse(
      '${AppConstants.geminiBaseUrl}/${AppConstants.geminiModel}:generateContent?key=$apiKey',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [{'text': '$system\n\n$user'}]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
      },
    });

    final response = await http
        .post(url, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 15));

    if (!response.statusCode.toString().startsWith('2')) {
      throw Exception('Gemini HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text == null) throw Exception('Gemini empty response');

    return _parseAIJson(text);
  }

  // ── Tier 2: OpenRouter implementation (model rotation) ───────────────────

  Future<_AIChatResponse> _tryOpenRouter(String system, String user) async {
    Exception? lastError;

    for (final model in AppConstants.openRouterModels) {
      try {
        final response = await http.post(
          Uri.parse(AppConstants.openRouterUrl),
          headers: {
            'Authorization': 'Bearer ${AppConstants.openRouterKey}',
            'Content-Type': 'application/json',
            'HTTP-Referer': 'https://ibnusinasudrajat.netlify.app',
            'X-Title': 'IbnuTify',
          },
          body: jsonEncode({
            'model': model,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          }),
        ).timeout(const Duration(seconds: 20));

        final result = jsonDecode(response.body) as Map<String, dynamic>;

        if (result['error'] != null) {
          lastError = Exception(result['error']['message']);
          continue;
        }

        final content = result['choices']?[0]?['message']?['content'] as String?;
        if (content == null) {
          lastError = Exception('OpenRouter empty content');
          continue;
        }

        return _parseAIJson(content);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
      }
    }

    throw lastError ?? Exception('All OpenRouter models failed');
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  _AIChatResponse _parseAIJson(String raw) {
    // Bersihkan kemungkinan markdown code block
    final cleaned = raw
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    final json = jsonDecode(cleaned) as Map<String, dynamic>;
    
    final rawSongIds = json['songIds'] as List? ?? [];
    final songIds = rawSongIds.map((e) {
      if (e is num) return e.toInt();
      if (e is String) return int.tryParse(e) ?? 0;
      return 0;
    }).where((id) => id > 0).toList();

    final rawSongs = json['songs'] as List? ?? [];
    final songsList = rawSongs.map((e) {
      if (e is Map<String, dynamic>) {
        final idVal = e['id'];
        int parsedId = 0;
        if (idVal is num) {
          parsedId = idVal.toInt();
        } else if (idVal is String) {
          parsedId = int.tryParse(idVal) ?? 0;
        }
        return _RecommendedSong(
          id: parsedId,
          title: e['title'] as String? ?? '',
          artist: e['artist'] as String? ?? '',
        );
      }
      return const _RecommendedSong(id: 0, title: '', artist: '');
    }).where((s) => s.title.isNotEmpty).toList();

    return _AIChatResponse(
      chatResponse: json['chatResponse'] as String? ?? 'Ini rekomendasiku!',
      playlistName: json['playlistName'] as String? ?? 'AI Mix',
      songIds: songIds,
      songs: songsList,
    );
  }

  AIChatMessage _buildMessage(_AIChatResponse resp, List<SongModel> allSongs) {
    final matched = <SongModel>[];

    // 1. Coba cocokkan menggunakan songIds
    for (final id in resp.songIds) {
      final song = allSongs.where((s) => s.id == id).firstOrNull;
      if (song != null && !matched.contains(song)) {
        matched.add(song);
      }
    }

    // Helper untuk normalisasi teks
    String normalize(String text) {
      return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
    }

    // 2. Coba cocokkan menggunakan nama & artis dari daftar songs
    for (final rec in resp.songs) {
      // Jika ID-nya sudah cocok di atas, lewati
      if (matched.any((s) => s.id == rec.id)) continue;

      final normRecTitle = normalize(rec.title);
      final normRecArtist = normalize(rec.artist);

      // Cari lagu lokal yang memiliki kecocokan judul dan artis
      final song = allSongs.where((s) {
        final normTitle = normalize(s.title);
        final normArtist = normalize(s.artist);

        // Jika judul persis sama (diabaikan case & simbol)
        if (normTitle == normRecTitle) {
          // Jika artis cocok atau salah satunya unknown
          if (normRecArtist.isEmpty || 
              normArtist.isEmpty || 
              normArtist.contains(normRecArtist) || 
              normRecArtist.contains(normArtist)) {
            return true;
          }
        }
        return false;
      }).firstOrNull;

      if (song != null && !matched.contains(song)) {
        matched.add(song);
      }
    }

    return AIChatMessage(
      role: ChatRole.ai,
      content: resp.chatResponse,
      recommendedSongs: matched.isNotEmpty ? matched : null,
      pendingPlaylistName: matched.isNotEmpty ? resp.playlistName : null,
    );
  }

  // ─── Legacy: analyzeLibraryMoods ──────────────────────────────────────────

  Future<List<AIMood>> analyzeLibraryMoods(List<SongModel> songs) async {
    if (songs.isEmpty) return [];

    final songListText = songs
        .map((s) => 'ID: ${s.id}, Title: ${s.title}, Artist: ${s.artist}')
        .join('\n');

    final prompt =
        'Berikut adalah daftar lagu di library musik saya:\n$songListText\n\n'
        'Tolong analisis lagu-lagu tersebut dan kelompokkan ke dalam maksimal 4 '
        'kategori "Mood" yang unik. Kembalikan hasilnya dalam format JSON array '
        'dengan struktur: [{"mood": string, "songIds": [int], "description": string}]. '
        'Hanya kembalikan JSON, tanpa teks tambahan.';

    final url = Uri.parse(
      '${AppConstants.geminiBaseUrl}/${AppConstants.geminiModel}:generateContent?key=$apiKey',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [{'text': prompt}]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
      },
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
        if (text == null) return [];
        final List<dynamic> list = jsonDecode(text);
        return list.map((j) => AIMood.fromJson(j as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
