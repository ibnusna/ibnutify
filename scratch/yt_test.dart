import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() async {
  final yt = YoutubeExplode();
  final manifest = await yt.videos.streamsClient.getManifest(VideoId('dQw4w9WgXcQ'));
  for (var stream in manifest.muxed) {
    print('Quality: ${stream.videoQuality}, Res: ${stream.videoResolution}, Container: ${stream.container.name}, Codec: ${stream.videoCodec}');
  }
  yt.close();
}
