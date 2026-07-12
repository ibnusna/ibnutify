void main() {
  final uri = Uri.parse('https://lrclib.net/api/get').replace(queryParameters: {
    'track_name': "As If It's Your Last",
    'artist_name': 'BLACKPINK'
  });
  print(uri);
}
