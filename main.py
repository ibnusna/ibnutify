import os
import re
import html
import requests
import yt_dlp
import io
import time
import json
import urllib.parse
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, TALB, APIC, USLT, TCON, TDRC, WXXX, SYLT

DOWNLOAD_DIR = "Downloaded Music"

def init_dir():
    if not os.path.exists(DOWNLOAD_DIR):
        os.makedirs(DOWNLOAD_DIR)

def get_lyrics(title, artist):
    try:
        query_artist = urllib.parse.quote(artist)
        query_title = urllib.parse.quote(title)
        url = f"https://lrclib.net/api/get?artist_name={query_artist}&track_name={query_title}"
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            plain = data.get('plainLyrics', 'Lirik tidak ditemukan.')
            synced = data.get('syncedLyrics')
            return plain, synced
    except requests.RequestException:
        return 'Lirik tidak ditemukan (network error).', None
    return 'Lirik tidak ditemukan.', None

def get_itunes_metadata(title, artist):
    try:
        query = urllib.parse.quote(f"{artist} {title}")
        url = f"https://itunes.apple.com/search?term={query}&entity=song&limit=1"
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get('resultCount', 0) > 0:
                result = data['results'][0]
                genre = result.get('primaryGenreName', '')
                release_date = result.get('releaseDate', '')
                year = release_date[:4] if release_date else ''
                return genre, year
    except requests.RequestException:
        pass
    return '', ''

def scrape_track_metadata(spotify_url):
    track_id_match = re.search(r'/track/([a-zA-Z0-9]+)', spotify_url)
    if not track_id_match:
        track_id_match = re.search(r'spotify:track:([a-zA-Z0-9]+)', spotify_url)
        
    if not track_id_match: 
        return None
        
    track_id = track_id_match.group(1)
    retries = 3
    
    for attempt in range(retries):
        try:
            embed_url = f'https://open.spotify.com/embed/track/{track_id}'
            headers = {'User-Agent': 'Mozilla/5.0'}
            response = requests.get(embed_url, headers=headers, timeout=10)
            
            match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', response.text)
            
            title = 'Unknown Title'
            artist = 'Unknown Artist'
            album = 'Unknown Album'
            cover_url = None
            release_year = ''

            if match:
                data = json.loads(match.group(1))
                entity = data['props']['pageProps']['state']['data']['entity']
                
                title = entity.get('title') or entity.get('name') or 'Unknown Title'
                artists = entity.get('artists', [])
                artist = artists[0]['name'] if artists else entity.get('subtitle', 'Unknown Artist')
                images = entity.get('visualIdentity', {}).get('image', [])
                cover_url = images[-1]['url'] if images else None
                
                release_date = entity.get('releaseDate', {}).get('isoString', '')
                if release_date:
                    release_year = release_date[:4]
                    
                return {
                    'title': title,
                    'artist': artist,
                    'album': album,
                    'cover_url': cover_url,
                    'year': release_year
                }
        except Exception as e:
            print(f"Scraping attempt {attempt+1}/{retries} failed: {e}")
            if attempt < retries - 1:
                time.sleep(1)
                continue
    return None

def download_and_convert(track_info, target_folder):
    title = track_info['title']
    artist = track_info['artist']
    search_query = f'"{artist}" "{title}" "provided to youtube"'
    clean_title = re.sub(r'[\\/*?:"<>|]', "", title)
    output_path = os.path.join(target_folder, clean_title)
    final_filepath = f"{output_path}.mp3"

    file_exists = False
    for root_dir, dirs, files in os.walk(DOWNLOAD_DIR):
        if f"{clean_title}.mp3" in files:
            file_exists = True
            break

    if file_exists:
        print(f"[!] {clean_title}.mp3 sudah ada. Skip download.")
        return final_filepath, "skipped", None

    print(f"[*] Mengunduh: {title} - {artist}")
    youtube_url = None

    def progress_hook(d):
        if d['status'] == 'finished':
            print(f"\n[+] Unduhan audio selesai. Tunggu bentar")

    ydl_opts = {
        'format': 'bestaudio/best',
        'postprocessors': [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '320',
        }],
        'postprocessor_args': [
            '-af', 
            'loudnorm=I=-16:TP=-1.5:LRA=11,bass=g=4,treble=g=3'
        ],
        'outtmpl': output_path + '.%(ext)s',
        'default_search': 'ytsearch1',
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
        'progress_hooks': [progress_hook],
        'extractor_args': {
            'youtube': {
                'player_client': ['android', 'web']
            }
        },
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(search_query, download=True)
            if 'entries' in info and len(info['entries']) > 0:
                youtube_url = info['entries'][0].get('webpage_url')
            else:
                youtube_url = info.get('webpage_url')
        
        if not os.path.exists(final_filepath):
            raise RuntimeError("Konversi FFmpeg gagal, file MP3 tidak dibuat.")
        
        return final_filepath, "success", youtube_url
        
    except Exception as e:
        print(f"[-] Download Error for '{search_query}': {str(e)}")
        return None, "failed", None

def add_metadata(filepath, track_info, youtube_url):
    print(f"[*] Menambahkan metadata ke file...")
    try:
        audio = MP3(filepath, ID3=ID3)
        try:
            audio.add_tags()
        except Exception:
            pass
        
        audio.tags.delall('APIC')
        audio.tags.delall('USLT')
        
        audio.tags.add(TIT2(encoding=3, text=track_info['title']))
        audio.tags.add(TPE1(encoding=3, text=track_info['artist']))
        audio.tags.add(TALB(encoding=3, text=track_info['album']))
        
        if track_info.get('year'):
            audio.tags.add(TDRC(encoding=3, text=track_info['year']))
            
        if track_info.get('genre'):
            audio.tags.add(TCON(encoding=3, text=track_info['genre']))
            
        if youtube_url:
            audio.tags.add(WXXX(encoding=3, desc='YouTube Source', url=youtube_url))
        
        if track_info.get('cover_url'):
            try:
                response = requests.get(track_info['cover_url'], timeout=15)
                if response.status_code == 200:
                    image_data = io.BytesIO(response.content).read()
                    audio.tags.add(APIC(
                        encoding=3,
                        mime='image/jpeg',
                        type=3, 
                        desc='Cover',
                        data=image_data
                    ))
            except Exception:
                pass

        if track_info.get('lyrics'):
            audio.tags.add(USLT(encoding=3, lang='eng', desc='desc', text=track_info['lyrics']))
            
        if track_info.get('synced_lyrics'):
            # Save as .lrc file next to .mp3
            lrc_filepath = filepath.rsplit('.', 1)[0] + '.lrc'
            with open(lrc_filepath, 'w', encoding='utf-8') as f:
                f.write(track_info['synced_lyrics'])
                
            # Parse and save as SYLT tag in ID3
            sylt_data = []
            for line in track_info['synced_lyrics'].split('\n'):
                match = re.match(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)', line)
                if match:
                    m, s, ms_part, text = match.groups()
                    ms = int(ms_part)
                    if len(ms_part) == 2:
                        ms *= 10
                    total_ms = int(m) * 60000 + int(s) * 1000 + ms
                    sylt_data.append((text.strip(), total_ms))
            
            if sylt_data:
                audio.tags.add(SYLT(encoding=3, lang='eng', format=2, type=1, desc='desc', text=sylt_data))
        
        audio.save()
        print("[+] Metadata berhasil ditambahkan.")
        
    except Exception as e:
        print(f"[-] Warning: Gagal menambah metadata - {str(e)}")

def main():
    init_dir()
    print("=========================================")
    print("        Spotify CLI Downloader           ")
    print("=========================================")
    spotify_url = input("Masukkan URL Spotify Track: ").strip()
    
    if not spotify_url:
        print("URL tidak boleh kosong!")
        return
        
    if "track" not in spotify_url:
        print("Saat ini hanya mendukung URL Spotify Track tunggal (bukan playlist).")
        return

    print("\n[*] Mengambil metadata dari Spotify...")
    track_info = scrape_track_metadata(spotify_url)
    
    if not track_info:
        print("[-] Gagal mengambil data dari Spotify.")
        return
        
    print(f"[+] Lagu ditemukan: {track_info['title']} - {track_info['artist']}")
    
    print("[*] Mengambil data tambahan (Genre, Tahun rilis, Lirik)...")
    itunes_genre, itunes_year = get_itunes_metadata(track_info['title'], track_info['artist'])
    
    if itunes_genre:
        track_info['genre'] = itunes_genre
        print(f"  - Genre: {itunes_genre}")
    
    if not track_info.get('year') and itunes_year:
        track_info['year'] = itunes_year
        print(f"  - Tahun rilis: {itunes_year}")
    elif track_info.get('year'):
        print(f"  - Tahun rilis: {track_info['year']}")
        
    lyrics, synced_lyrics = get_lyrics(track_info['title'], track_info['artist'])
    if lyrics and 'tidak ditemukan' not in lyrics:
        track_info['lyrics'] = lyrics
        if synced_lyrics:
            track_info['synced_lyrics'] = synced_lyrics
            print("  - Lirik: Ditemukan (dengan format SRT/Sinkronisasi)")
        else:
            print("  - Lirik: Ditemukan (hanya teks)")
    else:
        print("  - Lirik: Tidak ditemukan")

    mp3_filepath, status, youtube_url = download_and_convert(track_info, DOWNLOAD_DIR)
    
    if status == "success":
        add_metadata(mp3_filepath, track_info, youtube_url)
        print(f"\n[+] Selesai! Lagu tersimpan di: {mp3_filepath}")
    elif status == "skipped":
        print(f"\n[+] Lagu sudah ada di folder: {mp3_filepath}")
    else:
        print("\n[-] Proses gagal.")

if __name__ == "__main__":
    main()