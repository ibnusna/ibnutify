# downloader.py — IbnuTify Spotify Downloader (Chaquopy/Android Edition)
#
# Diadaptasi dari main.py untuk berjalan di dalam Chaquopy (Python 3.10, ARM64 Android).
# Tidak ada input() — semua parameter diterima dari Kotlin via MethodChannel.
# Progress disimpan di modul-level dict agar bisa di-polling oleh Dart.
#
# Fungsi yang di-expose ke Kotlin:
#   - get_track_metadata(spotify_url)       -> JSON string
#   - download_track(spotify_url, download_dir, ffmpeg_path)  -> JSON string
#   - get_download_progress()               -> JSON string

import os
import re
import html
import json
import time
import io
import threading
import urllib.parse

# ─── Module-level progress state (thread-safe via lock) ─────────────────────

_progress_lock = threading.Lock()
_download_progress = {
    "status": "idle",          # idle | fetching_metadata | downloading | converting | tagging | done | error | skipped
    "percent": 0.0,
    "eta_seconds": 0,
    "speed_str": "",
    "current_title": "",
    "current_artist": "",
    "file_path": "",
    "error": "",
    "total_songs": 1,
    "current_song_index": 1,
}

_debug_lock = threading.Lock()
_debug_logs = []

def _add_debug_log(msg):
    # Print to console/logcat as well
    print("[Downloader Py] " + msg)
    with _debug_lock:
        _debug_logs.append(msg)
        if len(_debug_logs) > 1000:
            _debug_logs.pop(0)

def get_download_log():
    """Mengembalikan seluruh log debug sebagai string terpisah baris baru."""
    with _debug_lock:
        return "\n".join(_debug_logs)

class YtdlpLogger:
    def debug(self, msg):
        # yt-dlp prints progress status to debug, but we only want other interesting logs
        if "[download]" in msg and "%" in msg:
            # Let progress_hook handle download percent logging, avoid spamming logs
            return
        _add_debug_log("[DEBUG] " + msg)

    def info(self, msg):
        _add_debug_log("[INFO] " + msg)

    def warning(self, msg):
        _add_debug_log("[WARNING] " + msg)

    def error(self, msg):
        _add_debug_log("[ERROR] " + msg)


def _set_progress(**kwargs):
    with _progress_lock:
        _download_progress.update(kwargs)


def get_download_progress():
    """Polling endpoint — dipanggil Kotlin setiap ~800ms saat download aktif."""
    with _progress_lock:
        return json.dumps(_download_progress)


# ─── Metadata helpers (dari main.py) ─────────────────────────────────────────

def _scrape_track_metadata(spotify_url):
    """Scrape judul, artis, album, cover_url, dan tahun dari Spotify embed page."""
    try:
        import requests
    except ImportError as e:
        _add_debug_log("[ERROR] ImportError in _scrape_track_metadata: " + str(e))
        return None

    track_id_match = re.search(r'/track/([a-zA-Z0-9]+)', spotify_url)
    if not track_id_match:
        track_id_match = re.search(r'spotify:track:([a-zA-Z0-9]+)', spotify_url)
    if not track_id_match:
        _add_debug_log("[ERROR] Could not extract track ID from URL: " + str(spotify_url))
        return None

    track_id = track_id_match.group(1)
    _add_debug_log("Extracted track ID: " + track_id)

    for attempt in range(3):
        try:
            embed_url = 'https://open.spotify.com/embed/track/{}'.format(track_id)
            headers = {'User-Agent': 'Mozilla/5.0'}
            response = requests.get(embed_url, headers=headers, timeout=15)
            
            if response.status_code != 200:
                _add_debug_log("[WARNING] Spotify returned HTTP {}".format(response.status_code))

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

                title = entity.get('title') or entity.get('name') or 'Unknown Title'
                artists = entity.get('artists', [])
                artist = artists[0]['name'] if artists else entity.get('subtitle', 'Unknown Artist')

                # Album dari entity
                album_data = entity.get('albumOfTrack', {})
                album = album_data.get('name', 'Unknown Album') if album_data else 'Unknown Album'

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
                    'year': release_year,
                }
            else:
                _add_debug_log("[WARNING] __NEXT_DATA__ not found in response text on attempt {}".format(attempt + 1))
        except Exception as e:
            _add_debug_log("[WARNING] Exception during scrape attempt {}: {}".format(attempt + 1, str(e)))
            if attempt < 2:
                time.sleep(1)
                continue
            
    _add_debug_log("[ERROR] Failed to scrape track metadata after 3 attempts.")
    return None


def _get_itunes_metadata(title, artist):
    """Ambil genre, tahun rilis, dan album dari iTunes API sebagai fallback/pengaya."""
    try:
        import requests
        query = urllib.parse.quote('{} {}'.format(artist, title))
        url = 'https://itunes.apple.com/search?term={}&entity=song&limit=5'.format(query)
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get('resultCount', 0) > 0:
                # Cari hasil yang paling cocok judulnya
                results = data['results']
                best = results[0]
                for r in results:
                    if r.get('trackName', '').lower() == title.lower():
                        best = r
                        break
                genre = best.get('primaryGenreName', '')
                release_date = best.get('releaseDate', '')
                year = release_date[:4] if release_date else ''
                album = best.get('collectionName', '')
                return genre, year, album
    except Exception:
        pass
    return '', '', ''


def _get_lyrics(title, artist):
    """Ambil lirik dari lrclib.net. Return (plain_lyrics, synced_lyrics)."""
    try:
        import requests
        query_artist = urllib.parse.quote(artist)
        query_title = urllib.parse.quote(title)
        url = 'https://lrclib.net/api/get?artist_name={}&track_name={}'.format(
            query_artist, query_title
        )
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            plain = data.get('plainLyrics', 'Lirik tidak ditemukan.')
            synced = data.get('syncedLyrics')
            return plain, synced
    except Exception:
        return 'Lirik tidak ditemukan (network error).', None
    return 'Lirik tidak ditemukan.', None


# ─── Public: get_track_metadata ───────────────────────────────────────────────

def get_track_metadata(spotify_url):
    """
    Ambil metadata lagu dari Spotify URL saja (tanpa download).
    Return JSON: {success, title, artist, album, year, cover_url, error}
    """
    _set_progress(status='fetching_metadata', current_title='', current_artist='')
    track_info = _scrape_track_metadata(spotify_url)
    if not track_info:
        _set_progress(status='error', error='Gagal mengambil metadata dari Spotify.')
        return json.dumps({
            'success': False,
            'error': 'Gagal mengambil metadata dari Spotify. Cek URL atau koneksi internet.'
        })

    itunes_genre, itunes_year, itunes_album = _get_itunes_metadata(track_info['title'], track_info['artist'])
    if itunes_genre:
        track_info['genre'] = itunes_genre
    if not track_info.get('year') and itunes_year:
        track_info['year'] = itunes_year
    # Gunakan album dari iTunes jika Spotify tidak mengembalikan album
    if track_info.get('album', 'Unknown Album') == 'Unknown Album' and itunes_album:
        track_info['album'] = itunes_album

    _set_progress(
        status='idle',
        current_title=track_info['title'],
        current_artist=track_info['artist'],
    )
    return json.dumps({
        'success': True,
        'title': track_info.get('title', ''),
        'artist': track_info.get('artist', ''),
        'album': track_info.get('album', ''),
        'year': track_info.get('year', ''),
        'cover_url': track_info.get('cover_url', ''),
        'genre': track_info.get('genre', ''),
    })


# ─── Public: download_track ───────────────────────────────────────────────────

def download_track(spotify_url, download_dir, ffmpeg_path=''):
    """
    Download satu track dari Spotify URL.

    Args:
        spotify_url  : URL Spotify track.
        download_dir : Path absolut ke direktori output di Android (e.g. /storage/emulated/0/Download/Ibnutify).
        ffmpeg_path  : Path ke binary ffmpeg (opsional; jika kosong, yt-dlp pakai m4a/best).

    Return JSON: {success, status, title, artist, album, file_path, error}
    """
    global _debug_logs
    with _debug_lock:
        _debug_logs = []

    _add_debug_log("=========================================")
    _add_debug_log("Starting download process for Spotify URL: {}".format(spotify_url))
    _add_debug_log("Download directory: {}".format(download_dir))
    _add_debug_log("Passed FFmpeg path: {}".format(ffmpeg_path))

    _set_progress(
        status='fetching_metadata',
        percent=0.0,
        eta_seconds=0,
        speed_str='',
        current_title='',
        current_artist='',
        file_path='',
        error='',
        total_songs=1,
        current_song_index=1,
    )

    # ── 1. Ambil metadata Spotify ─────────────────────────────────────────────
    _add_debug_log("Step 1: Scrape Spotify metadata...")
    track_info = _scrape_track_metadata(spotify_url)
    if not track_info:
        err = 'Gagal mengambil metadata dari Spotify. Cek URL atau koneksi.'
        _add_debug_log("[ERROR] Spotify metadata scraping failed.")
        _set_progress(status='error', error=err)
        return json.dumps({'success': False, 'status': 'error', 'error': err})

    _add_debug_log("Spotify metadata scraped successfully:")
    _add_debug_log("  Title: {}".format(track_info.get('title')))
    _add_debug_log("  Artist: {}".format(track_info.get('artist')))
    _add_debug_log("  Album: {}".format(track_info.get('album')))
    _add_debug_log("  Year: {}".format(track_info.get('year')))
    _add_debug_log("  Cover URL: {}".format(track_info.get('cover_url')))

    _set_progress(
        current_title=track_info['title'],
        current_artist=track_info['artist'],
    )

    # ── 2. Pengaya metadata (iTunes + lirik) ──────────────────────────────────
    _add_debug_log("Step 2: Scrape iTunes metadata helper...")
    itunes_genre, itunes_year, itunes_album = _get_itunes_metadata(track_info['title'], track_info['artist'])
    if itunes_genre:
        track_info['genre'] = itunes_genre
        _add_debug_log("  iTunes Genre: {}".format(itunes_genre))
    if not track_info.get('year') and itunes_year:
        track_info['year'] = itunes_year
        _add_debug_log("  iTunes Year: {}".format(itunes_year))
    if track_info.get('album', 'Unknown Album') == 'Unknown Album' and itunes_album:
        track_info['album'] = itunes_album
        _add_debug_log("  iTunes Album: {}".format(itunes_album))

    _add_debug_log("Step 3: Fetch lyrics from LRCLIB...")
    lyrics, synced_lyrics = _get_lyrics(track_info['title'], track_info['artist'])
    if lyrics and 'tidak ditemukan' not in lyrics:
        track_info['lyrics'] = lyrics
        _add_debug_log("  Lyrics found.")
        if synced_lyrics:
            track_info['synced_lyrics'] = synced_lyrics
            _add_debug_log("  Synced lyrics (.lrc format) found.")
    else:
        _add_debug_log("  Lyrics not found or error occurred.")

    # ── 3. Tentukan folder output ─────────────────────────────────────────────
    # Struktur: Ibnutify/{Album}/song.mp3  (jika ada album)
    #           Ibnutify/song.mp3          (jika album tidak diketahui)
    album_name = track_info.get('album', '').strip()
    if album_name and album_name.lower() not in ('unknown album', ''):
        clean_album = re.sub(r'[\\/*?:"<>|]', '', album_name)
        target_folder = os.path.join(download_dir, clean_album)
    else:
        target_folder = download_dir

    _add_debug_log("Target output folder: {}".format(target_folder))
    if not os.path.exists(target_folder):
        os.makedirs(target_folder)
        _add_debug_log("  Created target directory.")

    # ── 4. Buat nama file ─────────────────────────────────────────────────────
    clean_title = re.sub(r'[\\/*?:"<>|]', '', track_info['title'])
    output_path = os.path.join(target_folder, clean_title)

    # ── 5. Cek apakah sudah ada ───────────────────────────────────────────────
    use_ffmpeg = bool(ffmpeg_path and os.path.exists(ffmpeg_path))
    final_ext = 'mp3' if use_ffmpeg else 'm4a'
    final_filepath = '{}.{}'.format(output_path, final_ext)

    _add_debug_log("FFmpeg configuration:")
    _add_debug_log("  FFmpeg path: {}".format(ffmpeg_path))
    _add_debug_log("  FFmpeg exists: {}".format(os.path.exists(ffmpeg_path) if ffmpeg_path else False))
    _add_debug_log("  use_ffmpeg: {}".format(use_ffmpeg))
    _add_debug_log("  Expected extension: {}".format(final_ext))
    _add_debug_log("  Target filepath: {}".format(final_filepath))

    # Cek di seluruh Ibnutify folder
    _add_debug_log("Checking if file already exists in download folder...")
    file_exists = False
    for root_dir, dirs, files in os.walk(download_dir):
        if '{}.mp3'.format(clean_title) in files or '{}.m4a'.format(clean_title) in files:
            file_exists = True
            for f in files:
                if f.startswith(clean_title):
                    final_filepath = os.path.join(root_dir, f)
            break

    if file_exists:
        _add_debug_log("File already exists at: {}. Skipping download.".format(final_filepath))
        _set_progress(status='skipped', percent=100.0, file_path=final_filepath)
        return json.dumps({
            'success': True,
            'status': 'skipped',
            'title': track_info['title'],
            'artist': track_info['artist'],
            'album': track_info.get('album', ''),
            'file_path': final_filepath,
            'error': '',
        })

    # ── 6. Build yt-dlp options ───────────────────────────────────────────────
    _add_debug_log("Step 4: Configure yt-dlp options...")
    _set_progress(status='downloading', percent=0.0)

    def _progress_hook(d):
        """Hook dipanggil yt-dlp setiap kali ada update progress."""
        status = d.get('status', '')
        if status == 'downloading':
            total = d.get('total_bytes') or d.get('total_bytes_estimate') or 0
            downloaded = d.get('downloaded_bytes', 0)
            percent = (downloaded / total * 100.0) if total > 0 else 0.0
            eta = d.get('eta', 0) or 0
            speed = d.get('_speed_str', '') or d.get('speed_str', '') or ''
            _set_progress(
                status='downloading',
                percent=round(percent, 1),
                eta_seconds=int(eta),
                speed_str=speed,
            )
        elif status == 'finished':
            _add_debug_log("yt-dlp download finished, starting audio post-processing...")
            _set_progress(status='converting', percent=99.0, eta_seconds=0)

    search_query = 'ytsearch1:{} {} audio'.format(
        track_info['artist'], track_info['title']
    )
    _add_debug_log("Search Query: {}".format(search_query))

    ydl_opts = {
        'default_search': 'ytsearch1',
        'noplaylist': True,
        'quiet': False,
        'no_warnings': False,
        'logger': YtdlpLogger(),
        'progress_hooks': [_progress_hook],
        'outtmpl': output_path + '.%(ext)s',
        # Retry & timeout settings untuk Android/koneksi lambat
        'retries': 10,
        'fragment_retries': 10,
        'socket_timeout': 60,
        'http_chunk_size': 1048576,  # 1MB per chunk
        'extractor_retries': 3,
        'extractor_args': {
            'youtube': {
                'player_client': ['android', 'web']
            }
        },
    }

    if use_ffmpeg:
        # MP3 dengan loudnorm (Option A — ffmpeg tersedia via libffmpeg.so)
        _add_debug_log("Configuring yt-dlp with FFmpeg integration for MP3 audio extraction.")
        ydl_opts['format'] = 'bestaudio/best'
        ydl_opts['postprocessors'] = [{
            'key': 'FFmpegExtractAudio',
            'preferredcodec': 'mp3',
            'preferredquality': '320',
        }]
        ydl_opts['postprocessor_args'] = [
            '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11,bass=g=4,treble=g=3'
        ]
        ydl_opts['ffmpeg_location'] = ffmpeg_path
    else:
        # Tanpa ffmpeg — paksa ambil format m4a (aac)
        _add_debug_log("Configuring yt-dlp without FFmpeg. Forcing bestaudio[ext=m4a] download.")
        ydl_opts['format'] = 'bestaudio[ext=m4a]/bestaudio/best'
        final_filepath = output_path  # path tanpa ext, akan dicari nanti

    youtube_url = None

    try:
        _add_debug_log("Step 5: Run yt-dlp YoutubeDL.extract_info...")
        import yt_dlp
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(search_query, download=True)
            if info and 'entries' in info and len(info['entries']) > 0:
                youtube_url = info['entries'][0].get('webpage_url')
            elif info:
                youtube_url = info.get('webpage_url')
        
        _add_debug_log("yt-dlp extract_info succeeded. YouTube URL: {}".format(youtube_url))

        # Cari file hasil download — scan folder karena ext bisa webm/opus/m4a/mp3
        _add_debug_log("Scanning target folder for downloaded file...")
        found = None
        for f in os.listdir(target_folder):
            name_no_ext = os.path.splitext(f)[0]
            if name_no_ext == clean_title:
                found = os.path.join(target_folder, f)
                break

        if found:
            final_filepath = found
            _add_debug_log("Found downloaded file: {}".format(final_filepath))
        elif not os.path.exists(final_filepath):
            raise RuntimeError('File output tidak ditemukan setelah download di folder: {}'.format(target_folder))

    except Exception as e:
        import traceback
        tb = traceback.format_exc()
        err = 'Download gagal: {}\nTraceback:\n{}'.format(str(e), tb)
        _add_debug_log("[ERROR] Exception occurred during download:\n" + err)
        _set_progress(status='error', error=str(e))
        return json.dumps({
            'success': False,
            'status': 'error',
            'title': track_info.get('title', ''),
            'artist': track_info.get('artist', ''),
            'album': track_info.get('album', ''),
            'file_path': '',
            'error': str(e),
        })

    # ── 7. Tambahkan metadata ─────────────────────────────────────────────────
    _add_debug_log("Step 6: Writing metadata tags (mutagen)...")
    _set_progress(status='tagging', percent=99.5)
    try:
        if final_filepath.endswith('.mp3'):
            _add_debug_log("  Writing MP3 ID3 metadata...")
            _add_mp3_metadata(final_filepath, track_info, youtube_url)
        else:
            # Untuk format non-MP3 (webm/opus/m4a) — tambah tag via mutagen
            _add_debug_log("  Writing generic (M4A/MP4) metadata...")
            _add_generic_metadata(final_filepath, track_info, youtube_url)
        _add_debug_log("  Metadata writing finished successfully.")
    except Exception as tag_err:
        _add_debug_log("[WARNING] Metadata tagging failed: {}".format(tag_err))

    _add_debug_log("Download track completed successfully!")
    _add_debug_log("Final file path: {}".format(final_filepath))
    _add_debug_log("=========================================")
    _set_progress(status='done', percent=100.0, file_path=final_filepath)

    return json.dumps({
        'success': True,
        'status': 'done',
        'title': track_info['title'],
        'artist': track_info['artist'],
        'album': track_info.get('album', ''),
        'file_path': final_filepath,
        'error': '',
    })


# ─── ID3 Metadata writer ──────────────────────────────────────────────────────

def _add_mp3_metadata(filepath, track_info, youtube_url):
    """Tulis ID3 tags ke file MP3: judul, artis, album, cover art, lirik, tahun, genre."""
    try:
        from mutagen.mp3 import MP3
        from mutagen.id3 import ID3, TIT2, TPE1, TALB, APIC, USLT, TCON, TDRC, WXXX, SYLT
        import requests

        audio = MP3(filepath, ID3=ID3)
        try:
            audio.add_tags()
        except Exception:
            pass

        audio.tags.delall('APIC')
        audio.tags.delall('USLT')

        audio.tags.add(TIT2(encoding=3, text=track_info.get('title', '')))
        audio.tags.add(TPE1(encoding=3, text=track_info.get('artist', '')))
        audio.tags.add(TALB(encoding=3, text=track_info.get('album', '')))

        if track_info.get('year'):
            audio.tags.add(TDRC(encoding=3, text=track_info['year']))

        if track_info.get('genre'):
            audio.tags.add(TCON(encoding=3, text=track_info['genre']))

        if youtube_url:
            audio.tags.add(WXXX(encoding=3, desc='YouTube Source', url=youtube_url))

        # Cover art
        if track_info.get('cover_url'):
            try:
                r = requests.get(track_info['cover_url'], timeout=15)
                if r.status_code == 200:
                    audio.tags.add(APIC(
                        encoding=3,
                        mime='image/jpeg',
                        type=3,
                        desc='Cover',
                        data=io.BytesIO(r.content).read(),
                    ))
            except Exception:
                pass

        # Plain lyrics
        if track_info.get('lyrics'):
            audio.tags.add(USLT(encoding=3, lang='eng', desc='desc', text=track_info['lyrics']))

        # Synced lyrics (.lrc + SYLT tag)
        if track_info.get('synced_lyrics'):
            lrc_path = filepath.rsplit('.', 1)[0] + '.lrc'
            try:
                with open(lrc_path, 'w', encoding='utf-8') as f:
                    f.write(track_info['synced_lyrics'])
            except Exception:
                pass

            sylt_data = []
            for line in track_info['synced_lyrics'].split('\n'):
                m = re.match(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)', line)
                if m:
                    mins, secs, ms_part, text = m.groups()
                    ms = int(ms_part)
                    if len(ms_part) == 2:
                        ms *= 10
                    total_ms = int(mins) * 60000 + int(secs) * 1000 + ms
                    sylt_data.append((text.strip(), total_ms))

            if sylt_data:
                audio.tags.add(
                    SYLT(encoding=3, lang='eng', format=2, type=1, desc='desc', text=sylt_data)
                )

        audio.save()
    except Exception:
        # Metadata gagal tidak boleh hentikan proses utama
        pass


def _add_generic_metadata(filepath, track_info, youtube_url):
    """Tulis metadata ke file MP4/M4A jika ffmpeg tidak tersedia."""
    if not filepath.endswith('.m4a'):
        # Jika fallback yt-dlp bukan m4a (misal webm/opus), tag tidak didukung dengan baik
        return

    try:
        from mutagen.mp4 import MP4, MP4Cover
        import requests

        audio = MP4(filepath)

        audio['\xa9nam'] = track_info.get('title', '')
        audio['\xa9ART'] = track_info.get('artist', '')
        audio['\xa9alb'] = track_info.get('album', '')
        
        if track_info.get('year'):
            audio['\xa9day'] = track_info['year']
            
        if track_info.get('genre'):
            audio['\xa9gen'] = track_info['genre']

        if youtube_url:
            audio['\xa9cmt'] = 'YouTube Source: ' + youtube_url

        if track_info.get('lyrics'):
            audio['\xa9lyr'] = track_info['lyrics']

        # Cover art
        if track_info.get('cover_url'):
            try:
                r = requests.get(track_info['cover_url'], timeout=15)
                if r.status_code == 200:
                    audio['covr'] = [
                        MP4Cover(r.content, imageformat=MP4Cover.FORMAT_JPEG)
                    ]
            except Exception:
                pass

        audio.save()
    except Exception:
        pass
