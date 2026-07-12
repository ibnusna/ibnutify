import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Robust ID3v2 USLT lyrics extractor for Android MP3 files.
///
/// Key fixes vs previous version:
///
/// 1. CONTENT DESCRIPTION BUG ("descBetapa..."):
///    Previous parser assumed Latin-1 null = single 0x00 byte.
///    Samsung Music tags description dengan "desc\x00" (5 bytes) — artinya
///    description field bisa berisi text sebelum null terminator.
///    Fix: scan byte-by-byte sampai null byte, bukan hardcode skip.
///
/// 2. UTF-16 DESCRIPTION BUG:
///    UTF-16 encoding (byte 1) null terminator = 2 bytes \x00\x00.
///    Tapi description bisa odd-length dengan padding byte.
///    Fix: scan 2-byte pairs, break pada \x00\x00 dengan alignment.
///
/// 3. EXTENDED HEADER SUPPORT:
///    ID3v2.3+ bisa punya extended header (flag bit 6).
///    Previous parser mengabaikan ini, offset jadi salah.
///    Fix: detect dan skip extended header.
///
/// 4. MULTI-FRAME FALLBACK:
///    Jika USLT pertama kosong/gagal, coba USLT berikutnya.
///
/// 5. SAMSUNG SPECIFIC HANDLING:
///    Samsung terkadang menggunakan UTF-8 (encoding=3) untuk description
///    tapi menyimpan newlines sebagai \r\n atau bahkan \r saja.
class LyricsService {
  LyricsService._();
  static final LyricsService instance = LyricsService._();

  // Cache: songId → lyrics (null = confirmed no lyrics)
  final _cache = <int, String?>{};

  Future<String?> getLyrics(int songId, String fileUri) async {
    if (_cache.containsKey(songId)) return _cache[songId];
    try {
      final result = await _extractLyricsFromFile(fileUri);
      _cache[songId] = result;
      return result;
    } catch (_) {
      _cache[songId] = null;
      return null;
    }
  }

  void clearCache() => _cache.clear();
  void evict(int songId) => _cache.remove(songId);

  // ─── File I/O ──────────────────────────────────────────────────────────────

  Future<String?> _extractLyricsFromFile(String fileUri) async {
    final path = _uriToPath(fileUri);
    if (path == null) return null;

    // 1. Check for sidecar .lrc file (created by downloader.py)
    try {
      // e.g. /storage/emulated/0/Download/Ibnutify/Song.mp3 -> .../Song.lrc
      final lrcPath = path.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.lrc');
      final lrcFile = File(lrcPath);
      if (await lrcFile.exists()) {
        final lrcContent = await lrcFile.readAsString();
        if (lrcContent.trim().isNotEmpty) {
          return lrcContent;
        }
      }
    } catch (_) {
      // fallback to reading ID3 tag
    }

    final file = File(path);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      // Read 10-byte ID3 header
      final hdr = Uint8List(10);
      if (await raf.readInto(hdr) < 10) return null;

      // Verify ID3v2 magic: "ID3"
      if (hdr[0] != 0x49 || hdr[1] != 0x44 || hdr[2] != 0x33) return null;

      final version = hdr[3]; // 2, 3, or 4
      final flags = hdr[5];
      final hasExtendedHeader = (flags & 0x40) != 0;

      // Parse syncsafe tag size (always syncsafe in all ID3v2 versions)
      final tagSize = _syncsafeInt(hdr, 6);
      if (tagSize <= 0 || tagSize > 10 * 1024 * 1024) return null;

      // Read full tag body
      final body = Uint8List(tagSize);
      final read = await raf.readInto(body);
      if (read < tagSize) return null;

      return _parseTagBody(body, version, hasExtendedHeader);
    } finally {
      await raf.close();
    }
  }

  // ─── Tag Body Parser ───────────────────────────────────────────────────────

  String? _parseTagBody(Uint8List body, int version, bool hasExtendedHeader) {
    int offset = 0;

    // Skip extended header if present
    if (hasExtendedHeader && offset + 4 <= body.length) {
      int extSize;
      if (version >= 4) {
        extSize = _syncsafeInt(body, offset);
      } else {
        extSize = _bigEndianInt(body, offset, 4);
      }
      offset += extSize;
      if (offset >= body.length) return null;
    }

    // Frame header sizes per version:
    // ID3v2.2: frame id = 3 bytes, size = 3 bytes, no flags
    // ID3v2.3+: frame id = 4 bytes, size = 4 bytes, flags = 2 bytes
    final isV22 = version == 2;
    final frameIdLen = isV22 ? 3 : 4;
    final frameSizeLen = isV22 ? 3 : 4;
    final frameFlagsLen = isV22 ? 0 : 2;
    final frameHeaderLen = frameIdLen + frameSizeLen + frameFlagsLen;

    // Collect all USLT frames (take best one)
    final candidates = <String>[];

    while (offset + frameHeaderLen <= body.length) {
      // Check for padding (all zeros)
      if (body[offset] == 0x00) break;

      final frameId = String.fromCharCodes(
        body.sublist(offset, offset + frameIdLen),
      );

      int frameSize;
      if (version >= 4) {
        // ID3v2.4: frame size is syncsafe
        frameSize = _syncsafeInt(body, offset + frameIdLen);
      } else {
        // ID3v2.2 and 2.3: regular big-endian
        frameSize = _bigEndianInt(body, offset + frameIdLen, frameSizeLen);
      }

      if (frameSize <= 0) {
        // Try stepping by 1 byte to recover from corruption
        offset++;
        continue;
      }

      if (offset + frameHeaderLen + frameSize > body.length) break;

      final dataStart = offset + frameHeaderLen;
      final dataEnd = dataStart + frameSize;
      final frameData = body.sublist(dataStart, dataEnd);

      // Match USLT (v2.3/2.4) or ULT (v2.2)
      if (frameId == 'USLT' || frameId == 'ULT\x00' || frameId == 'ULT') {
        final lyrics = _decodeUslt(frameData, version);
        if (lyrics != null && lyrics.isNotEmpty) {
          candidates.add(lyrics);
        }
      }

      offset = dataEnd;
    }

    if (candidates.isEmpty) return null;

    // Prefer longest lyrics (most complete)
    candidates.sort((a, b) => b.length.compareTo(a.length));
    return candidates.first;
  }

  // ─── USLT Decoder ─────────────────────────────────────────────────────────

  /// Decodes USLT frame data.
  ///
  /// USLT frame structure:
  ///   [0]     encoding byte (0=Latin-1, 1=UTF-16, 2=UTF-16BE, 3=UTF-8)
  ///   [1..3]  language code (3 ASCII bytes, e.g. "eng")
  ///   [4..]   content description (null-terminated, encoding-aware)
  ///           + lyrics text (rest of frame)
  String? _decodeUslt(Uint8List data, int version) {
    if (data.length < 5) return null;

    final encoding = data[0];
    // Language is bytes 1–3, skip to byte 4
    int pos = 4;

    // ── Skip content description ────────────────────────────────────────────
    // This is the critical fix: "descBetapa..." means description was NOT skipped.
    // Samsung Music often sets description to "desc" (ASCII) even with UTF-16 encoding.
    if (encoding == 1 || encoding == 2) {
      // UTF-16: description ends at \x00\x00 (aligned to 2-byte boundary)
      // We scan byte pairs. Also handle: Samsung sometimes has only \x00 padding.
      pos = _skipUtf16NullTerminator(data, pos);
    } else {
      // Latin-1 (0) or UTF-8 (3): description ends at single \x00
      pos = _skipLatin1NullTerminator(data, pos);
    }

    if (pos >= data.length) return null;

    // ── Decode lyrics text ──────────────────────────────────────────────────
    final textBytes = data.sublist(pos);
    if (textBytes.isEmpty) return null;

    String raw;
    try {
      switch (encoding) {
        case 0: // ISO-8859-1 / Latin-1
          raw = latin1.decode(textBytes, allowInvalid: true);
          break;
        case 1: // UTF-16 with BOM
        case 2: // UTF-16 BE
          raw = _decodeUtf16(textBytes, bigEndian: encoding == 2);
          break;
        case 3: // UTF-8
          raw = utf8.decode(textBytes, allowMalformed: true);
          break;
        default:
          // Unknown encoding — try UTF-8, fallback to Latin-1
          try {
            raw = utf8.decode(textBytes, allowMalformed: false);
          } catch (_) {
            raw = latin1.decode(textBytes, allowInvalid: true);
          }
      }
    } catch (_) {
      // Last resort: treat as codepoints
      raw = String.fromCharCodes(textBytes);
    }

    return _cleanLyrics(raw);
  }

  // ─── Null Terminator Scanners ─────────────────────────────────────────────

  /// Advances [pos] past a Latin-1/UTF-8 null-terminated string.
  int _skipLatin1NullTerminator(Uint8List data, int pos) {
    while (pos < data.length && data[pos] != 0x00) {
      pos++;
    }
    return pos + 1; // skip the null byte itself
  }

  /// Advances [pos] past a UTF-16 null-terminated string (\x00\x00).
  ///
  /// Samsung quirk: description may be odd-length or have BOM.
  /// We scan for the double-null without strict 2-byte alignment.
  int _skipUtf16NullTerminator(Uint8List data, int pos) {
    // Handle BOM in description (uncommon but possible)
    if (pos + 1 < data.length &&
        ((data[pos] == 0xFF && data[pos + 1] == 0xFE) ||
            (data[pos] == 0xFE && data[pos + 1] == 0xFF))) {
      pos += 2;
    }

    // Scan for 0x00 0x00 sequence
    while (pos + 1 < data.length) {
      if (data[pos] == 0x00 && data[pos + 1] == 0x00) {
        pos += 2;
        // Skip any alignment padding byte
        if (pos < data.length && data[pos] == 0x00) pos++;
        return pos;
      }
      // In some encoders, description is stored as Latin-1 even with UTF-16 flag
      // If we hit a non-null byte followed by \x00 (i.e., Latin-1 in a UTF-16 field)
      // we advance by 1 to avoid infinite loop
      if (data[pos] == 0x00 && pos + 1 < data.length && data[pos + 1] != 0x00) {
        pos++;
        continue;
      }
      pos++;
    }
    return pos;
  }

  // ─── UTF-16 Decoder ───────────────────────────────────────────────────────

  String _decodeUtf16(Uint8List bytes, {bool bigEndian = false}) {
    if (bytes.length < 2) return '';

    int start = 0;
    bool be = bigEndian;

    // Check BOM
    if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
      be = false; // LE
      start = 2;
    } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
      be = true; // BE
      start = 2;
    }

    final buf = StringBuffer();
    int i = start;
    while (i + 1 < bytes.length) {
      final hi = be ? bytes[i] : bytes[i + 1];
      final lo = be ? bytes[i + 1] : bytes[i];
      final cp = (hi << 8) | lo;
      if (cp == 0) break; // null terminator
      // Handle surrogate pairs (UTF-16 supplementary chars)
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 3 < bytes.length) {
        final hi2 = be ? bytes[i + 2] : bytes[i + 3];
        final lo2 = be ? bytes[i + 3] : bytes[i + 2];
        final cp2 = (hi2 << 8) | lo2;
        if (cp2 >= 0xDC00 && cp2 <= 0xDFFF) {
          final full = 0x10000 + ((cp - 0xD800) << 10) + (cp2 - 0xDC00);
          buf.writeCharCode(full);
          i += 4;
          continue;
        }
      }
      buf.writeCharCode(cp);
      i += 2;
    }
    return buf.toString();
  }

  // ─── Lyrics Cleaner ───────────────────────────────────────────────────────

  /// Cleans raw lyrics text:
  /// - Normalize line endings
  /// - Strip BOM / null bytes / control characters
  /// - Remove common junk prefixes ("desc")
  /// - Trim excessive blank lines (max 2 consecutive)
  String? _cleanLyrics(String raw) {
    if (raw.isEmpty) return null;

    String s = raw;

    // Remove BOM
    s = s.replaceAll('\uFEFF', '');

    // Remove null bytes
    s = s.replaceAll('\x00', '');

    // Remove lines that are only timestamps or metadata (e.g. "[ti:Song]", "[ar:Artist]")
    s = s.replaceAll(RegExp(r'^\[[a-zA-Z]+:[^\]]*\]\s*$', multiLine: true), '');

    // Normalize line endings: \r\n → \n, \r → \n
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // Remove null-like chars that cause "desc" prefix artifacts
    // (Some encoders write description as "desc" with the lyrics immediately after,
    // separated only by the null byte. If the null was missed, strip it here.)
    if (s.startsWith('desc') || s.startsWith('Desc')) {
      // Only strip if "desc" is clearly not lyrics (< 10 chars before a newline or letter)
      final afterDesc = s.substring(4);
      if (afterDesc.startsWith('\x00') || afterDesc.isEmpty) {
        s = afterDesc.replaceFirst('\x00', '');
      } else if (!afterDesc.startsWith(' ') && !afterDesc.startsWith('\n')) {
        // "descBetapa..." — strip the 4-char prefix
        s = afterDesc;
      }
    }

    // Collapse 3+ consecutive blank lines into 2
    s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // Final trim
    s = s.trim();

    // Minimum viable lyrics: at least 10 chars
    return s.length >= 10 ? s : null;
  }

  // ─── Integer helpers ──────────────────────────────────────────────────────

  /// Syncsafe integer: each byte uses only 7 bits.
  static int _syncsafeInt(Uint8List buf, int offset) {
    if (offset + 3 >= buf.length) return 0;
    return ((buf[offset] & 0x7F) << 21) |
        ((buf[offset + 1] & 0x7F) << 14) |
        ((buf[offset + 2] & 0x7F) << 7) |
        (buf[offset + 3] & 0x7F);
  }

  /// Big-endian integer of [len] bytes.
  static int _bigEndianInt(Uint8List buf, int offset, int len) {
    int result = 0;
    for (int i = 0; i < len; i++) {
      result = (result << 8) | buf[offset + i];
    }
    return result;
  }

  // ─── URI resolution ───────────────────────────────────────────────────────

  /// Resolves file:// or plain path URIs to a filesystem path.
  String? _uriToPath(String uri) {
    // file:///storage/emulated/0/...
    if (uri.startsWith('file:///')) {
      return Uri.decodeComponent(uri.replaceFirst('file://', ''));
    }
    if (uri.startsWith('file://')) {
      return Uri.decodeComponent(uri.replaceFirst('file://', ''));
    }
    // Plain absolute path
    if (uri.startsWith('/')) return uri;
    // content:// — not directly readable without platform channel
    return null;
  }
}
