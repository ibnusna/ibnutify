import 'dart:io';

void main() async {
  final client = HttpClient();
  final uri = Uri.parse("https://lrclib.net/api/get?artist_name=Payung%20Teduh&track_name=Akad");
  final request = await client.getUrl(uri);
  request.headers.add('User-Agent', 'IbnuTify/1.0 (ibnutify@example.com)');
  final response = await request.close();
  print('Status: ${response.statusCode}');
  client.close();
}
