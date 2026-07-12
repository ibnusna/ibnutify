import 'dart:io';
import 'dart:convert';

void main() async {
  final uri = Uri.parse("https://somacro.com/api/v1/lyrics?artist=BLACKPINK&title=As%20If%20It%27s%20Your%20Last");
  print('Fetching: $uri');
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close().timeout(Duration(seconds: 10));
    print('Status: ${response.statusCode}');
    final body = await response.transform(utf8.decoder).join();
    print('Body snippet: ${body.length > 200 ? body.substring(0, 200) : body}');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
