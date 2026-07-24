import os
import re
import html
import threading
import requests
import yt_dlp
import io
import time
import json
from tkinter import Tk, Label, Button, Entry, ttk, messagebox, BOTH, Frame, Canvas, Scrollbar
from tkinter import *
from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TPE1, TALB, APIC, USLT

from PIL import Image, ImageTk

SPOTIFY_CLIENT_ID = '455644341c7a4fb1b6132e84c5dd3eb6'
SPOTIFY_CLIENT_SECRET = '2c0c2cb91da84f90af051a8c34ae0ffc'

DOWNLOAD_DIR = "Downloaded Music"

# Memaksa menggunakan mode scraping (API dinonaktifkan karena butuh Premium)
sp = None

class SpotifyDownloaderApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Spotify Downloader")
        self.root.geometry("800x600")
        self.root.resizable(False, False)
        self.root.configure(bg='#121212')
        
        self.download_start_time = 0
        self.current_track_info = {}
        self.total_tracks = 0
        self.current_track_index = 0

        if not os.path.exists(DOWNLOAD_DIR):
            os.makedirs(DOWNLOAD_DIR)

        self.setup_styles()
        self.create_widgets()

    def setup_styles(self):
        style = ttk.Style()
        style.theme_use('clam')
        
        style.configure("Title.TLabel", 
                       background="#121212", 
                       foreground="#1DB954", 
                       font=('Segoe UI', 32, 'bold'))
        
        style.configure("Subtitle.TLabel", 
                       background="#121212", 
                       foreground="#B3B3B3", 
                       font=('Segoe UI', 11))
        
        style.configure("TrackTitle.TLabel", 
                       background="#121212", 
                       foreground="#FFFFFF", 
                       font=('Segoe UI', 18, 'bold'))
        
        style.configure("TrackInfo.TLabel", 
                       background="#121212", 
                       foreground="#B3B3B3", 
                       font=('Segoe UI', 12))
        
        style.configure("Progress.TLabel", 
                       background="#121212", 
                       foreground="#1DB954", 
                       font=('Segoe UI', 16, 'bold'))
        
        style.configure("Speed.TLabel", 
                       background="#121212", 
                       foreground="#FFFFFF", 
                       font=('Segoe UI', 11))
        
        style.configure("Input.TLabel", 
                       background="#121212", 
                       foreground="#FFFFFF", 
                       font=('Segoe UI', 12, 'bold'))
        
        style.configure("Spotify.TButton", 
                       padding=(20, 12),
                       relief="flat", 
                       background="#1DB954", 
                       foreground="#FFFFFF", 
                       font=('Segoe UI', 12, 'bold'),
                       borderwidth=0)
        
        style.map("Spotify.TButton", 
                 background=[('active', '#1ED760'), ('pressed', '#1AA34A'), ('disabled', '#535353')])
        
        style.configure("Spotify.TEntry", 
                       padding=12,
                       relief="flat", 
                       font=('Segoe UI', 11),
                       fieldbackground="#404040",
                       foreground="#FFFFFF",
                       borderwidth=1,
                       insertcolor="#FFFFFF")
        
        style.configure("Spotify.Horizontal.TProgressbar",
                       background="#1DB954",
                       troughcolor="#404040",
                       borderwidth=0,
                       lightcolor="#1DB954",
                       darkcolor="#1DB954",
                       relief="flat")

    def create_widgets(self):
        main_container = Frame(self.root, bg="#121212")
        main_container.pack(fill=BOTH, expand=True)

        header_frame = Frame(main_container, bg="#121212", height=100)
        header_frame.pack(fill=X, padx=40, pady=(30, 20))
        header_frame.pack_propagate(False)

        title_label = ttk.Label(header_frame, text="Spotify Downloader", style="Title.TLabel")
        title_label.pack(anchor=W)
        
        subtitle_label = ttk.Label(header_frame, text="By Ibnu Sina Sudrajat", style="Subtitle.TLabel")
        subtitle_label.pack(anchor=W, pady=(5, 0))

        input_section = Frame(main_container, bg="#121212")
        input_section.pack(fill=X, padx=40, pady=(0, 30))
        
        url_label = ttk.Label(input_section, text="URL Spotify Track atau Playlist:", style="Input.TLabel")
        url_label.pack(anchor=W, pady=(0, 8))
        
        entry_frame = Frame(input_section, bg="#121212")
        entry_frame.pack(fill=X, pady=(0, 15))
        
        self.url_entry = ttk.Entry(entry_frame, style="Spotify.TEntry", font=('Segoe UI', 11))
        self.url_entry.pack(side=LEFT, fill=X, expand=True, padx=(0, 15))
        
        self.download_button = ttk.Button(entry_frame, text="Download", 
                                        style="Spotify.TButton", 
                                        command=self.start_download_thread)
        self.download_button.pack(side=RIGHT)

        progress_section = Frame(main_container, bg="#121212")
        progress_section.pack(fill=BOTH, expand=True, padx=40, pady=(0, 20))

        self.progress_card = Frame(progress_section, bg="#1A1A1A", relief=FLAT, bd=0)
        self.progress_card.pack(fill=BOTH, expand=True)

        card_content = Frame(self.progress_card, bg="#1A1A1A")
        card_content.pack(fill=BOTH, expand=True, padx=30, pady=30)

        track_header = Frame(card_content, bg="#1A1A1A")
        track_header.pack(fill=X, pady=(0, 25))

        self.cover_label = Label(track_header, bg="#1A1A1A", width=12, height=6, 
                                relief="flat", bd=0)
        self.cover_label.pack(side=LEFT, padx=(0, 20))

        track_details = Frame(track_header, bg="#1A1A1A")
        track_details.pack(side=LEFT, fill=BOTH, expand=True)

        self.track_title_label = ttk.Label(track_details, text="Pilih track untuk memulai download", 
                                          style="TrackTitle.TLabel")
        self.track_title_label.pack(anchor=W)

        self.artist_label = ttk.Label(track_details, text="", style="TrackInfo.TLabel")
        self.artist_label.pack(anchor=W, pady=(8, 0))

        self.album_label = ttk.Label(track_details, text="", style="TrackInfo.TLabel")
        self.album_label.pack(anchor=W, pady=(5, 0))

        progress_container = Frame(card_content, bg="#1A1A1A")
        progress_container.pack(fill=X, pady=(25, 0))

        self.progress_bar = ttk.Progressbar(progress_container, 
                                          style="Spotify.Horizontal.TProgressbar",
                                          orient=HORIZONTAL, 
                                          length=500, 
                                          mode='determinate')
        self.progress_bar.pack(fill=X, pady=(0, 15))

        progress_info_frame = Frame(progress_container, bg="#1A1A1A")
        progress_info_frame.pack(fill=X, pady=(0, 10))

        self.progress_percentage_label = ttk.Label(progress_info_frame, text="0%", style="Progress.TLabel")
        self.progress_percentage_label.pack(side=LEFT)

        self.download_speed_label = ttk.Label(progress_info_frame, text="", style="Speed.TLabel")
        self.download_speed_label.pack(side=RIGHT)

        time_info_frame = Frame(progress_container, bg="#1A1A1A")
        time_info_frame.pack(fill=X, pady=(0, 15))

        self.eta_label = ttk.Label(time_info_frame, text="", style="Speed.TLabel")
        self.eta_label.pack(side=LEFT)

        self.overall_progress_label = ttk.Label(time_info_frame, text="", style="Speed.TLabel")
        self.overall_progress_label.pack(side=RIGHT)

        self.status_label = ttk.Label(progress_container, text="Siap untuk download", style="TrackInfo.TLabel")
        self.status_label.pack(anchor=W, pady=(10, 0))

        footer_frame = Frame(main_container, bg="#121212", height=30)
        footer_frame.pack(fill=X)
        footer_frame.pack_propagate(False)
        
        footer_label = ttk.Label(footer_frame, text="© 2024 Spotify Downloader", style="Subtitle.TLabel")
        footer_label.pack(pady=8)

    def update_track_display(self, track_info, track_index):
        self.current_track_info = track_info
        self.track_title_label.config(text=track_info['title'])
        self.artist_label.config(text=f"Artis: {track_info['artist']}")
        self.album_label.config(text=f"Album: {track_info['album']}")
        self.overall_progress_label.config(text=f"{track_index + 1} / {self.total_tracks}")
        
        if track_info.get('cover_url'):
            self.load_cover_image(track_info['cover_url'])
        
        self.root.update_idletasks()

    def load_cover_image(self, cover_url):
        try:
            response = requests.get(cover_url, timeout=10)
            if response.status_code == 200:
                image = Image.open(io.BytesIO(response.content))
                image = image.resize((140, 140), Image.Resampling.LANCZOS)
                photo = ImageTk.PhotoImage(image)
                self.cover_label.config(image=photo, bg="#1A1A1A")
                self.cover_label.image = photo
        except Exception:
            pass

    def fetch_lyrics(self, title, artist):
        try:
            url = f"https://api.lyrics.ovh/v1/{artist}/{title}"
            response = requests.get(url, timeout=7)
            if response.status_code == 200:
                data = response.json()
                return data.get('lyrics', 'Lirik tidak ditemukan.')
        except requests.RequestException:
            return 'Lirik tidak ditemukan (network error).'
            return data.get('lyrics', 'Lirik tidak ditemukan.')
        except requests.RequestException:
            return 'Lirik tidak ditemukan (network error).'
        return 'Lirik tidak ditemukan.'

    def scrape_track_metadata(self, spotify_url):
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
                if match:
                    data = json.loads(match.group(1))
                    entity = data['props']['pageProps']['state']['data']['entity']
                    
                    title = entity.get('title') or entity.get('name') or 'Unknown Title'
                    
                    artists = entity.get('artists', [])
                    artist = artists[0]['name'] if artists else entity.get('subtitle', 'Unknown Artist')
                    
                    images = entity.get('visualIdentity', {}).get('image', [])
                    cover_url = images[-1]['url'] if images else None
                    
                    return {
                        'title': title,
                        'artist': artist,
                        'album': 'Unknown Album',
                        'cover_url': cover_url
                    }
            except Exception as e:
                print(f"Scraping attempt {attempt+1}/{retries} failed: {e}")
                if attempt < retries - 1:
                    time.sleep(1)
                    continue
        return None

    def get_tracks_from_url(self, spotify_url):
        tracks_to_download = []
        playlist_name = None
        try:
            if "track" in spotify_url:
                self.status_label.config(text="Mengambil informasi track...")
                self.root.update_idletasks()
                
                track_data = None
                
                # Attempt API first if available
                if sp:
                    try:
                        track = sp.track(spotify_url)
                        track_data = {
                            'title': track['name'], 
                            'artist': track['artists'][0]['name'], 
                            'album': track['album']['name'], 
                            'cover_url': track['album']['images'][0]['url'] if track['album']['images'] else None
                        }
                    except Exception as e:
                        print(f"API failed for track ({e}), trying fallback...")
                
                # Fallback to scraping
                if not track_data:
                    track_data = self.scrape_track_metadata(spotify_url)
                
                if track_data:
                    tracks_to_download.append(track_data)
                else:
                    raise Exception("Gagal mengambil metadata track via API maupun Scraping.")
            elif "playlist" in spotify_url:
                self.status_label.config(text="Mengambil informasi playlist...")
                self.root.update_idletasks()
                
                playlist_tracks = []
                try:
                    # Metode 1: API Resmi
                    if sp:
                        results = sp.playlist_items(spotify_url)
                        playlist_tracks = results['items']
                        while results['next']:
                            self.status_label.config(text=f"Memuat playlist... ({len(playlist_tracks)} track)")
                            self.root.update_idletasks()
                            results = sp.next(results)
                            playlist_tracks.extend(results['items'])
                    else:
                        raise Exception("API Init Failed")
                except Exception as e:
                    # Metode 2: Fallback Scraping + Batch API
                    self.status_label.config(text="Mengambil data melalui mode scraping...")
                    self.root.update_idletasks()
                    
                    headers = {
                        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
                        'Accept-Language': 'en-US,en;q=0.5',
                    }
                    try:
                        r = requests.get(spotify_url, headers=headers)
                        if r.status_code == 200:
                            title_match = re.search(r'<meta property="og:title" content="(.*?)"', r.text)
                            if title_match:
                                playlist_name = html.unescape(title_match.group(1))

                            # Cari Track ID dengan Regex
                            ids = list(set(re.findall(r'/track/([a-zA-Z0-9]{22})', r.text)))
                            if not ids:
                                # Coba regex alternatif jika ada variasi URL
                                ids = list(set(re.findall(r'spotify:track:([a-zA-Z0-9]{22})', r.text)))
                            
                            if not ids:
                                raise Exception("Tidak ada track ditemukan dengan metode alternatif.")

                            self.status_label.config(text=f"Ditemukan {len(ids)} track. Mengambil metadata...")
                            self.root.update_idletasks()

                            # Fetch metadata in batches of 50 (Spotify API limit)
                            # Using API if available for detailed metadata, else we have to guess or scrape individually
                            # Note: Scraping individually for 100s of tracks is slow and risks IP ban.
                            
                            
                            success_with_api = False
                            if sp:
                                try:
                                    for i in range(0, len(ids), 50):
                                        batch_ids = ids[i:i+50]
                                        tracks_data = sp.tracks(batch_ids)
                                        for t in tracks_data['tracks']:
                                            if t:
                                                playlist_tracks.append({'track': t})
                                    success_with_api = True
                                except Exception as e:
                                    success_with_api = False

                            if not success_with_api:
                                # Fallback: Scrape metadata for each track individually
                                self.status_label.config(text=f"Mode Tanpa API: Scrape {len(ids)} track satu per satu...")
                                self.root.update_idletasks()
                                
                                for i, track_id in enumerate(ids):
                                    self.status_label.config(text=f"Scraping info track {i+1}/{len(ids)}...")
                                    self.root.update_idletasks()
                                    
                                    # Fast embed scraping doesn't need long delay
                                    if i > 0: 
                                        time.sleep(0.1)

                                    track_url = f"https://open.spotify.com/track/{track_id}"
                                    meta = self.scrape_track_metadata(track_url)
                                    if meta:
                                        # Construct dummy track object to fit existing flow
                                        dummy_track = {
                                            'name': meta['title'],
                                            'artists': [{'name': meta['artist']}],
                                            'album': {
                                                'name': meta['album'],
                                                'images': [{'url': meta['cover_url']}] if meta['cover_url'] else []
                                            }
                                        }
                                        playlist_tracks.append({'track': dummy_track})
                        else:
                            raise Exception(f"Gagal akses halaman playlist: {r.status_code}")
                    except Exception as fallback_error:
                         raise Exception(f"Gagal mengambil data dari Spotify (API & Fallback).\nError 1: {str(e)}\nError 2: {str(fallback_error)}")
                
                for item in playlist_tracks:
                    track = item.get('track')
                    if track and track.get('name'):
                        tracks_to_download.append({
                            'title': track['name'], 
                            'artist': track['artists'][0]['name'], 
                            'album': track['album']['name'], 
                            'cover_url': track['album']['images'][0]['url'] if track['album']['images'] else None
                        })
            else:
                messagebox.showerror("URL Tidak Valid", "Masukkan URL Spotify Track atau Playlist yang valid.")
                return [], None
        except Exception as e:
            messagebox.showerror("Kesalahan Spotify", f"Tidak dapat mengambil data dari Spotify.\nError: {str(e)}")
            return [], None
        return tracks_to_download, playlist_name

    def format_speed(self, bytes_per_second):
        if bytes_per_second < 1024:
            return f"{bytes_per_second:.0f} B/s"
        elif bytes_per_second < 1024 * 1024:
            return f"{bytes_per_second / 1024:.1f} KB/s"
        else:
            return f"{bytes_per_second / (1024 * 1024):.1f} MB/s"

    def format_time(self, seconds):
        if seconds < 60:
            return f"{int(seconds)}s"
        elif seconds < 3600:
            return f"{int(seconds // 60)}m {int(seconds % 60)}s"
        else:
            return f"{int(seconds // 3600)}h {int((seconds % 3600) // 60)}m"

    def calculate_speed_and_eta(self, downloaded_bytes, total_bytes, percentage):
        current_time = time.time()
        
        if self.download_start_time == 0:
            self.download_start_time = current_time
            return 0, 0
        
        elapsed_time = current_time - self.download_start_time
        
        if elapsed_time < 1:
            return 0, 0
        
        speed = downloaded_bytes / elapsed_time
        
        if percentage > 0 and total_bytes > 0:
            remaining_bytes = total_bytes - downloaded_bytes
            if speed > 0:
                eta = remaining_bytes / speed
                return speed, eta
        
        return speed, 0

    def download_and_convert(self, track_info, track_index, target_folder):
        title = track_info['title']
        artist = track_info['artist']
        # Menggunakan parameter ini untuk memastikan YouTube memberikan "Art Track" (audio resmi tanpa intro video musik)
        search_query = f'"{artist}" "{title}" "provided to youtube"'
        clean_title = re.sub(r'[\\/*?:"<>|]', "", title)
        output_path = os.path.join(target_folder, clean_title)
        final_filepath = f"{output_path}.mp3"

        # Cek apakah file sudah ada di mana saja di dalam DOWNLOAD_DIR
        file_exists = False
        for root_dir, dirs, files in os.walk(DOWNLOAD_DIR):
            if f"{clean_title}.mp3" in files:
                file_exists = True
                break

        if file_exists:
            self.progress_bar['value'] = 100
            self.progress_percentage_label.config(text="100%")
            self.download_speed_label.config(text="Sudah ada (Skip)")
            self.eta_label.config(text="Melanjutkan ke track berikutnya...")
            self.status_label.config(text="Lagu sudah ada di folder download")
            self.root.update_idletasks()
            time.sleep(1)
            return final_filepath, "skipped"

        self.progress_bar['value'] = 0
        self.progress_percentage_label.config(text="0%")
        self.download_speed_label.config(text="Memulai...")
        self.eta_label.config(text="Menghubungkan...")
        self.status_label.config(text="Mencari dan mengunduh audio...")
        self.download_start_time = 0
        self.root.update_idletasks()

        def progress_hook(d):
            if d['status'] == 'downloading':
                try:
                    p_str = d.get('_percent_str', '0%').replace('%','').strip()
                    percentage = float(p_str)
                    self.progress_bar['value'] = percentage
                    self.progress_percentage_label.config(text=f"{int(percentage)}%")
                    self.status_label.config(text="Mengunduh audio dari YouTube...")
                    
                    downloaded_bytes = d.get('downloaded_bytes', 0)
                    total_bytes = d.get('total_bytes', 0) or d.get('total_bytes_estimate', 0)
                    
                    if downloaded_bytes > 0:
                        speed, eta = self.calculate_speed_and_eta(downloaded_bytes, total_bytes, percentage)
                        
                        if speed > 0:
                            self.download_speed_label.config(text=self.format_speed(speed))
                        
                        if eta > 0:
                            self.eta_label.config(text=f"Sisa: {self.format_time(eta)}")
                    
                    self.root.update_idletasks()
                except (ValueError, AttributeError, TypeError):
                    pass
            elif d['status'] == 'finished':
                self.progress_bar['value'] = 100
                self.progress_percentage_label.config(text="100%")
                self.download_speed_label.config(text="Selesai")
                self.eta_label.config(text="Memproses...")
                self.status_label.config(text="Mengkonversi dan menambahkan metadata...")
                self.root.update_idletasks()

        ydl_opts = {
            'format': 'bestaudio/best',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '320', # Memaksa output jadi 320kbps
            }],
'postprocessor_args': [
                '-af', 
                # Penjelasan Filter (Dibaca berurutan oleh FFmpeg):
                # 1. loudnorm: Ratakan volume dulu biar standar.
                # 2. bass=g=4: Tambah Bass 4dB (Nendang tapi gak pecah).
                # 3. treble=g=3: Tambah Treble 3dB (Biar vokal & cymbal jernih).
                # 4. extrastereo: Bikin sedikit lebih lebar (opsional, hapus jika tidak suka).
                'loudnorm=I=-16:TP=-1.5:LRA=11,bass=g=4,treble=g=3'
            ],
            'outtmpl': output_path + '.%(ext)s',
            'default_search': 'ytsearch1',
            'noplaylist': True,
            'quiet': False, # Enable output to see errors
            'noprogress': True,
            'progress_hooks': [progress_hook],
            'js_runtimes': {'node': {}}, # Enabled to process songs requiring JS runtime extraction
        }

        try:
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                ydl.download([search_query])
            
            if not os.path.exists(final_filepath):
                raise RuntimeError("Konversi FFmpeg gagal, file MP3 tidak dibuat.")
            
            return final_filepath, "success"
            
        except Exception as e:
            print(f"Download Error for '{search_query}': {str(e)}") # Print error to console
            self.status_label.config(text=f"Gagal: {str(e)}")
            return None, "failed"

    def add_metadata(self, filepath, track_info):
        self.status_label.config(text="Menambahkan metadata dan cover art...")
        self.root.update_idletasks()
        
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
            
            if track_info.get('cover_url'):
                try:
                    response = requests.get(track_info['cover_url'], timeout=15)
                    if response.status_code == 200:
                        image = Image.open(io.BytesIO(response.content))
                        jpeg_buffer = io.BytesIO()
                        image.convert('RGB').save(jpeg_buffer, format='JPEG')
                        
                        audio.tags.add(APIC(
                            encoding=3,
                            mime='image/jpeg',
                            type=3, 
                            desc='Cover',
                            data=jpeg_buffer.getvalue()
                        ))
                except Exception:
                    pass

            lyrics = self.fetch_lyrics(track_info['title'], track_info['artist'])
            audio.tags.add(USLT(encoding=3, lang='eng', desc='desc', text=lyrics))
            
            audio.save()
            
        except Exception as e:
            self.status_label.config(text=f"Warning: Gagal menambah metadata - {str(e)}")

    def start_download_thread(self):
        self.download_button.config(state="disabled")
        threading.Thread(target=self.run_download_process, daemon=True).start()

    def run_download_process(self):
        spotify_url = self.url_entry.get().strip()
        if not spotify_url:
            messagebox.showerror("Input Error", "Masukkan URL Spotify!")
            self.download_button.config(state="normal")
            return

        result = self.get_tracks_from_url(spotify_url)
        if not result or not result[0]:
            self.status_label.config(text="Gagal mengambil data dari Spotify")
            self.download_button.config(state="normal")
            return
            
        self.tracks_to_download, playlist_name = result

        target_folder = DOWNLOAD_DIR
        if playlist_name:
            clean_playlist_name = re.sub(r'[\\/*?:"<>|]', "", playlist_name)
            target_folder = os.path.join(DOWNLOAD_DIR, clean_playlist_name)
            if not os.path.exists(target_folder):
                os.makedirs(target_folder)

        self.total_tracks = len(self.tracks_to_download)

        successful_downloads = 0
        failed_downloads = []

        for i, track in enumerate(self.tracks_to_download):
            self.current_track_index = i
            self.update_track_display(track, i)

            mp3_filepath, status = self.download_and_convert(track, i, target_folder)
            
            if status == "success":
                self.add_metadata(mp3_filepath, track)
                successful_downloads += 1
                self.status_label.config(text="Download selesai!")
            elif status == "skipped":
                successful_downloads += 1
            elif status == "failed":
                failed_downloads.append(track['title'])
            
            time.sleep(0.5)
        
        self.status_label.config(text=f"Selesai! {successful_downloads}/{self.total_tracks} track berhasil")
        self.eta_label.config(text="")
        self.download_speed_label.config(text="")

        if failed_downloads:
            failed_list_str = "\n- ".join(failed_downloads)
            messagebox.showwarning("Beberapa Track Gagal", 
                                 f"Track yang gagal diunduh:\n- {failed_list_str}\n\n" +
                                 "Pastikan FFmpeg terinstall dan koneksi internet stabil.")
        else:
            messagebox.showinfo("Berhasil!", f"Semua {successful_downloads} track berhasil diunduh!\n" +
                               f"Lokasi: {DOWNLOAD_DIR}")
            
        self.download_button.config(state="normal")

if __name__ == "__main__":
    window = Tk()
    app = SpotifyDownloaderApp(window)
    window.mainloop()