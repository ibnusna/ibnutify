// chat_history_service.dart
// Menyimpan riwayat sesi chat AI Moods ke SharedPreferences.
// Setiap sesi punya: id, title (judul otomatis dari pesan pertama user), messages JSON, createdAt.
// Data hilang jika user clear app data — sesuai requirement.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Model ──────────────────────────────────────────────────────────────────

class ChatSessionMessage {
  final String role; // 'user' | 'ai'
  final String content;

  const ChatSessionMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatSessionMessage.fromJson(Map<String, dynamic> json) {
    return ChatSessionMessage(
      role: json['role'] as String? ?? 'ai',
      content: json['content'] as String? ?? '',
    );
  }
}

class ChatSession {
  final String id;
  final String title;
  final List<ChatSessionMessage> messages;
  final DateTime createdAt;

  const ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final msgs = (json['messages'] as List<dynamic>? ?? [])
        .map((m) => ChatSessionMessage.fromJson(m as Map<String, dynamic>))
        .toList();
    return ChatSession(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Obrolan',
      messages: msgs,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['createdAt'] as num? ?? 0).toInt(),
      ),
    );
  }

  ChatSession copyWith({String? title, List<ChatSessionMessage>? messages}) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt,
    );
  }
}

// ─── Service ─────────────────────────────────────────────────────────────────

class ChatHistoryService {
  static const _kStorageKey = 'ai_chat_sessions_v1';
  static const _kMaxSessions = 50; // Simpan max 50 sesi terakhir

  static final ChatHistoryService _instance = ChatHistoryService._();
  static ChatHistoryService get instance => _instance;
  ChatHistoryService._();

  Future<List<ChatSession>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      final sessions = list
          .map((e) => ChatSession.fromJson(e as Map<String, dynamic>))
          .toList();
      // Urutkan dari terbaru ke terlama
      sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      debugPrint('[ChatHistory] Loaded ${sessions.length} sessions from SharedPreferences');
      return sessions;
    } catch (e) {
      debugPrint('[ChatHistory] Load error: $e');
      return [];
    }
  }

  Future<void> saveSession(ChatSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadAll();

      // Hapus sesi lama dengan id yang sama (update)
      final filtered = existing.where((s) => s.id != session.id).toList();
      filtered.insert(0, session); // Tambah/update di depan

      // Batasi jumlah sesi
      final trimmed = filtered.take(_kMaxSessions).toList();

      final encoded = jsonEncode(trimmed.map((s) => s.toJson()).toList());
      await prefs.setString(_kStorageKey, encoded);
      debugPrint('[ChatHistory] Saved session "${session.title}" (id: ${session.id})');
    } catch (e) {
      debugPrint('[ChatHistory] Save error: $e');
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = await loadAll();
      final filtered = existing.where((s) => s.id != id).toList();
      await prefs.setString(
        _kStorageKey,
        jsonEncode(filtered.map((s) => s.toJson()).toList()),
      );
      debugPrint('[ChatHistory] Deleted session $id');
    } catch (e) {
      debugPrint('[ChatHistory] Delete error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kStorageKey);
      debugPrint('[ChatHistory] All sessions cleared');
    } catch (e) {
      debugPrint('[ChatHistory] ClearAll error: $e');
    }
  }

  /// Generate judul otomatis dari konten pesan pertama user (maks 40 karakter).
  static String generateTitle(String firstUserMessage) {
    final clean = firstUserMessage.trim().replaceAll('\n', ' ');
    if (clean.length <= 40) return clean;
    return '${clean.substring(0, 37)}...';
  }
}
