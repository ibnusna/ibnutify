import re, json, requests

track_id = '0qbRvZ1alpPGmV52wKb2gJ'
embed_url = f'https://open.spotify.com/embed/track/{track_id}'
headers = {'User-Agent': 'Mozilla/5.0'}
response = requests.get(embed_url, headers=headers, timeout=15)
match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', response.text)

if match:
    data = json.loads(match.group(1))
    entity = data['props']['pageProps']['state']['data']['entity']
    # dump all keys
    print(list(entity.keys()))
    # dump track info
    print("durationInfo:", entity.get('durationInfo'))
    print("durationMs:", entity.get('durationMs'))
    print("duration_ms:", entity.get('duration_ms'))
    import pprint
    # find duration recursively
    def find_duration(d):
        for k, v in d.items():
            if 'duration' in k.lower():
                print(f"{k}: {v}")
            if isinstance(v, dict):
                find_duration(v)
            elif isinstance(v, list):
                for item in v:
                    if isinstance(item, dict):
                        find_duration(item)
    find_duration(entity)
