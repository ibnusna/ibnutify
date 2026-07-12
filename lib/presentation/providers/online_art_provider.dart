import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/online_art_service.dart';

/// UI1: Provider family untuk path gambar artist dari internet.
/// Keyed by artist name. Returns null jika tidak ada / loading.
final artistImageProvider =
    FutureProvider.family<String?, String>((ref, artist) async {
  return OnlineArtService.instance.getArtistImagePath(artist);
});

/// UI1: Provider family untuk path cover album dari internet.
/// Keyed by "album|||artist" combined key.
final albumCoverOnlineProvider =
    FutureProvider.family<String?, String>((ref, albumArtistKey) async {
  final sep = albumArtistKey.indexOf('|||');
  if (sep < 0) return null;
  final album = albumArtistKey.substring(0, sep);
  final artist = albumArtistKey.substring(sep + 3);
  return OnlineArtService.instance.getAlbumCoverPath(album, artist);
});
