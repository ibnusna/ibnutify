import 'dart:io';
import 'dart:convert';

void main() async {
  final target = Uri.encodeComponent("https://lrclib.net/api/get?track_name=As If It's Your Last&artist_name=BLACKPINK");
  final uri = Uri.parse("https://api.allorigins.win/raw?url=\$target");
  print('Fetching: \$uri');
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.add('User-Agent', 'IbnuTify/1.0');
    final response = await request.close().timeout(Duration(seconds: 10));
    print('Status: \${response.statusCode}');
    final body = await response.transform(utf8.decoder).join();
    print('Body snippet: \${body.length > 200 ? body.substring(0, 200) : body}');
  } catch (e) {
    print('Error: \$e');
  } finally {
    client.close();
  }
}
