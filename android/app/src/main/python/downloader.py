# downloader.py — IbnuTify Spotify Downloader (Chaquopy/Android Edition)
#
# Diadaptasi dari main.py untuk berjalan di dalam Chaquopy (Python 3.8, ARM64 Android).
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
    except ImportError:
        return None

    track_id_match = re.search(r'/track/([a-zA-Z0-9]+)', spotify_url)
    if not track_id_match:
        track_id_match = re.search(r'spotify:track:([a-zA-Z0-9]+)', spotify_url)
    if not track_id_match:
        return None

    track_id = track_id_match.group(1)

    for attempt in range(3):
        try:
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
        except Exception as e:
            if attempt < 2:
                time.sleep(1)
                continue
    return None


def _get_itunes_metadata(title, artist):
    """Ambil genre dan tahun rilis dari iTunes API sebagai fallback/pengaya."""
    try:
        import requests
        query = urllib.parse.quote('{} {}'.format(artist, title))
        url = 'https://itunes.apple.com/search?term={}&entity=song&limit=1'.format(query)
        response = requests.get(url, timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get('resultCount', 0) > 0:
                result = data['results'][0]
                genre = result.get('primaryGenreName', '')
                release_date = result.get('releaseDate', '')
                year = release_date[:4] if release_date else ''
                return genre, year
    except Exception:
        pass
    return '', ''


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

    itunes_genre, itunes_year = _get_itunes_metadata(track_info['title'], track_info['artist'])
    if itunes_genre:
        track_info['genre'] = itunes_genre
    if not track_info.get('year') and itunes_year:
        track_info['year'] = itunes_year

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
    track_info = _scrape_track_metadata(spotify_url)
    if not track_info:
        err = 'Gagal mengambil metadata dari Spotify. Cek URL atau koneksi.'
        _set_progress(status='error', error=err)
        return json.dumps({'success': False, 'status': 'error', 'error': err})

    _set_progress(
        current_title=track_info['title'],
        current_artist=track_info['artist'],
    )

    # ── 2. Pengaya metadata (iTunes + lirik) ──────────────────────────────────
    itunes_genre, itunes_year = _get_itunes_metadata(track_info['title'], track_info['artist'])
    if itunes_genre:
        track_info['genre'] = itunes_genre
    if not track_info.get('year') and itunes_year:
        track_info['year'] = itunes_year

    lyrics, synced_lyrics = _get_lyrics(track_info['title'], track_info['artist'])
    if lyrics and 'tidak ditemukan' not in lyrics:
        track_info['lyrics'] = lyrics
        if synced_lyrics:
            track_info['synced_lyrics'] = synced_lyrics

    # ── 3. Tentukan folder output ─────────────────────────────────────────────
    # Struktur: Ibnutify/{Album}/song.mp3  (jika ada album)
    #           Ibnutify/song.mp3          (jika album tidak diketahui)
    album_name = track_info.get('album', '').strip()
    if album_name and album_name.lower() not in ('unknown album', ''):
        clean_album = re.sub(r'[\\/*?:"<>|]', '', album_name)
        target_folder = os.path.join(download_dir, clean_album)
    else:
        target_folder = download_dir

    if not os.path.exists(target_folder):
        os.makedirs(target_folder)

    # ── 4. Buat nama file ─────────────────────────────────────────────────────
    clean_title = re.sub(r'[\\/*?:"<>|]', '', track_info['title'])
    output_path = os.path.join(target_folder, clean_title)

    # ── 5. Cek apakah sudah ada ───────────────────────────────────────────────
    use_ffmpeg = bool(ffmpeg_path and os.path.exists(ffmpeg_path))
    final_ext = 'mp3' if use_ffmpeg else 'm4a'
    final_filepath = '{}.{}'.format(output_path, final_ext)

    # Cek di seluruh Ibnutify folder
    file_exists = False
    for root_dir, dirs, files in os.walk(download_dir):
        if '{}.mp3'.format(clean_title) in files or '{}.m4a'.format(clean_title) in files:
            file_exists = True
            for f in files:
                if f.startswith(clean_title):
                    final_filepath = os.path.join(root_dir, f)
            break

    if file_exists:
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
            _set_progress(status='converting', percent=99.0, eta_seconds=0)

    search_query = '"{}" "{}" "provided to youtube"'.format(
        track_info['artist'], track_info['title']
    )

    ydl_opts = {
        'default_search': 'ytsearch1',
        'noplaylist': True,
        'quiet': True,
        'no_warnings': True,
        'progress_hooks': [_progress_hook],
        'outtmpl': output_path + '.%(ext)s',
    }

    if use_ffmpeg:
        # MP3 dengan loudnorm (Option A — ffmpeg tersedia)
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
        # M4A tanpa ffmpeg (Option B — fallback jika ffmpeg tidak ada)
        ydl_opts['format'] = 'bestaudio[ext=m4a]/bestaudio/best'
        final_filepath = '{}.m4a'.format(output_path)

    youtube_url = None

    try:
        import yt_dlp
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(search_query, download=True)
            if info and 'entries' in info and len(info['entries']) > 0:
                youtube_url = info['entries'][0].get('webpage_url')
            elif info:
                youtube_url = info.get('webpage_url')

        # Cari file hasil download (ext bisa berubah)
        if not os.path.exists(final_filepath):
            # Cari file dengan nama yang sama tapi ext berbeda
            for f in os.listdir(target_folder):
                if f.startswith(clean_title + '.'):
                    final_filepath = os.path.join(target_folder, f)
                    break

        if not os.path.exists(final_filepath):
            raise RuntimeError('File output tidak ditemukan setelah download.')

    except Exception as e:
        err = 'Download gagal: {}'.format(str(e))
        _set_progress(status='error', error=err)
        return json.dumps({
            'success': False,
            'status': 'error',
            'title': track_info.get('title', ''),
            'artist': track_info.get('artist', ''),
            'album': track_info.get('album', ''),
            'file_path': '',
            'error': err,
        })

    # ── 7. Tambahkan ID3 metadata ─────────────────────────────────────────────
    _set_progress(status='tagging', percent=99.5)
    if final_filepath.endswith('.mp3'):
        _add_mp3_metadata(final_filepath, track_info, youtube_url)

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
