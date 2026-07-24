import re, json, requests

track_id = '6gkbtMtioHgtyGjrMel6ei'
embed_url = 'https://open.spotify.com/embed/track/{}'.format(track_id)
headers = {'User-Agent': 'Mozilla/5.0'}
response = requests.get(embed_url, headers=headers, timeout=15)

match = re.search(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    response.text
)

title = 'Unknown Title'
artist = 'Unknown Artist'
album = 'Unknown Album'
cover_url = None
release_year = ''

if match:
    data = json.loads(match.group(1))
    entity = data['props']['pageProps']['state']['data']['entity']
    
    # Let's print exactly what downloader.py does:
    title = entity.get('title') or entity.get('name') or 'Unknown Title'
    artists = entity.get('artists', [])
    artist = artists[0]['name'] if artists else entity.get('subtitle', 'Unknown Artist')
    
    album_data = entity.get('albumOfTrack', {})
    album = album_data.get('name', 'Unknown Album') if album_data else 'Unknown Album'
    
    images = entity.get('visualIdentity', {}).get('image', [])
    cover_url = images[-1]['url'] if images else None
    
    release_date = entity.get('releaseDate', {}).get('isoString', '')
    if release_date:
        release_year = release_date[:4]

    print(f"Title: {title}")
    print(f"Artist: {artist}")
    print(f"Album: {album}")
    print(f"Cover URL: {cover_url}")
    print(f"Year: {release_year}")
else:
    print("No __NEXT_DATA__")
