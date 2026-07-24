import re, json, requests

track_id = '6gkbtMtioHgtyGjrMel6ei'
embed_url = 'https://open.spotify.com/embed/track/{}'.format(track_id)
headers = {'User-Agent': 'Mozilla/5.0'}
response = requests.get(embed_url, headers=headers, timeout=15)

print(f"Status: {response.status_code}")
match = re.search(
    r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
    response.text
)
if match:
    print("Found __NEXT_DATA__")
    data = json.loads(match.group(1))
    try:
        entity = data['props']['pageProps']['state']['data']['entity']
        print(f"Title: {entity.get('name')}")
    except Exception as e:
        print(f"Error parsing json: {e}")
else:
    print("No __NEXT_DATA__ found!")
    # Let's save the HTML to see what changed
    with open("spotify_dump.html", "w", encoding="utf-8") as f:
        f.write(response.text)
    print("Saved to spotify_dump.html")
