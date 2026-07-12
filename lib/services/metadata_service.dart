import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

/// Service to extract custom metadata like YouTube URLs from ID3 tags.
class MetadataService {
  MetadataService._();
  static final MetadataService instance = MetadataService._();

  Future<String?> extractYoutubeUrl(String fileUri) async {
    final path = _uriToPath(fileUri);
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final raf = await file.open(mode: FileMode.read);
    try {
      final hdr = Uint8List(10);
      if (await raf.readInto(hdr) < 10) return null;

      if (hdr[0] != 0x49 || hdr[1] != 0x44 || hdr[2] != 0x33) return null;

      final version = hdr[3]; 
      final flags = hdr[5];
      final hasExtendedHeader = (flags & 0x40) != 0;

      final tagSize = _syncsafeInt(hdr, 6);
      if (tagSize <= 0 || tagSize > 10 * 1024 * 1024) return null;

      final body = Uint8List(tagSize);
      final read = await raf.readInto(body);
      if (read < tagSize) return null;

      return _parseWxxx(body, version, hasExtendedHeader);
    } catch (_) {
      return null;
    } finally {
      await raf.close();
    }
  }

  String? _parseWxxx(Uint8List body, int version, bool hasExtendedHeader) {
    int offset = 0;

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

    final isV22 = version == 2;
    final frameIdLen = isV22 ? 3 : 4;
    final frameSizeLen = isV22 ? 3 : 4;
    final frameFlagsLen = isV22 ? 0 : 2;
    final frameHeaderLen = frameIdLen + frameSizeLen + frameFlagsLen;

    while (offset + frameHeaderLen <= body.length) {
      if (body[offset] == 0x00) break;

      final frameId = String.fromCharCodes(
        body.sublist(offset, offset + frameIdLen),
      );

      int frameSize;
      if (version >= 4) {
        frameSize = _syncsafeInt(body, offset + frameIdLen);
      } else {
        frameSize = _bigEndianInt(body, offset + frameIdLen, frameSizeLen);
      }

      if (frameSize <= 0) {
        offset++;
        continue;
      }

      if (offset + frameHeaderLen + frameSize > body.length) break;

      final dataStart = offset + frameHeaderLen;
      final dataEnd = dataStart + frameSize;
      final frameData = body.sublist(dataStart, dataEnd);

      if (frameId == 'WXXX' || frameId == 'WXX') {
        final url = _decodeWxxx(frameData);
        if (url != null && url.contains('youtube.com')) {
          return url;
        }
      }

      offset = dataEnd;
    }

    return null;
  }

  String? _decodeWxxx(Uint8List data) {
    if (data.length < 2) return null;

    final encoding = data[0];
    int pos = 1;

    // Skip description (null terminated)
    if (encoding == 1 || encoding == 2) {
      // UTF-16
      while (pos + 1 < data.length) {
        if (data[pos] == 0x00 && data[pos + 1] == 0x00) {
          pos += 2;
          if (pos < data.length && data[pos] == 0x00) pos++;
          break;
        }
        pos++;
      }
    } else {
      // Latin-1 or UTF-8
      while (pos < data.length && data[pos] != 0x00) {
        pos++;
      }
      pos++; // skip null
    }

    if (pos >= data.length) return null;

    // URL is always Latin-1 encoded
    final urlBytes = data.sublist(pos);
    
    // Some encoders mistakenly null terminate the URL too
    int end = 0;
    while (end < urlBytes.length && urlBytes[end] != 0x00) {
      end++;
    }
    
    return latin1.decode(urlBytes.sublist(0, end), allowInvalid: true).trim();
  }

  static int _syncsafeInt(Uint8List buf, int offset) {
    if (offset + 3 >= buf.length) return 0;
    return ((buf[offset] & 0x7F) << 21) |
        ((buf[offset + 1] & 0x7F) << 14) |
        ((buf[offset + 2] & 0x7F) << 7) |
        (buf[offset + 3] & 0x7F);
  }

  static int _bigEndianInt(Uint8List buf, int offset, int len) {
    int result = 0;
    for (int i = 0; i < len; i++) {
      result = (result << 8) | buf[offset + i];
    }
    return result;
  }

  String? _uriToPath(String uri) {
    if (uri.startsWith('file:///')) {
      return Uri.decodeComponent(uri.replaceFirst('file://', ''));
    }
    if (uri.startsWith('file://')) {
      return Uri.decodeComponent(uri.replaceFirst('file://', ''));
    }
    if (uri.startsWith('/')) return uri;
    return null;
  }
}
