import re, json, requests
import urllib.parse
from pprint import pprint

spotify_url = 'https://open.spotify.com/track/0qbRvZ1alpPGmV52wKb2gJ'
track_id = '0qbRvZ1alpPGmV52wKb2gJ'
embed_url = f'https://open.spotify.com/embed/track/{track_id}'
headers = {'User-Agent': 'Mozilla/5.0'}
response = requests.get(embed_url, headers=headers, timeout=15)
match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', response.text)

if match:
    data = json.loads(match.group(1))
    entity = data['props']['pageProps']['state']['data']['entity']
    title = entity.get('title') or entity.get('name') or 'Unknown'
    artists = entity.get('artists', [])
    artist = artists[0]['name'] if artists else 'Unknown'
    duration_ms = entity.get('duration_ms', 0)
    duration_s = duration_ms / 1000
    
    print(f"Spotify Title: {title}")
    print(f"Spotify Artist: {artist}")
    print(f"Spotify Duration: {duration_s}s")
    
    # Check LRCLIB
    query_artist = urllib.parse.quote(artist)
    query_title = urllib.parse.quote(title)
    url = f'https://lrclib.net/api/get?artist_name={query_artist}&track_name={query_title}'
    r = requests.get(url)
    if r.status_code == 200:
        lrclib_data = r.json()
        lrc_duration = lrclib_data.get('duration')
        print(f"LRCLIB Duration: {lrc_duration}s")
    else:
        print("LRCLIB Not found")
        lrc_duration = duration_s
        
    target_duration = lrc_duration or duration_s

    # Now search youtube for 5 results
    import yt_dlp
    ydl_opts = {
        'default_search': 'ytsearch5',
        'quiet': True,
        'extract_flat': True,
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(f"{artist} {title}", download=False)
        entries = info.get('entries', [])
        print("\nYoutube Results:")
        for e in entries:
            dur = e.get('duration')
            title = e.get('title')
            url = e.get('url')
            diff = abs(dur - target_duration) if dur else 999
            print(f"- {dur}s (diff {diff:.1f}s): {title}")

