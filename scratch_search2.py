import yt_dlp
import sys
ydl_opts = {
    'default_search': 'ytsearch5',
    'quiet': False,
    'extract_flat': True,
}
try:
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info("Sal Priadi Foto kita blur", download=False)
        entries = info.get('entries', [])
        print("\nYoutube Results:")
        for e in entries:
            dur = e.get('duration')
            title = e.get('title')
            print(f"- {dur}s : {title}")
except Exception as e:
    print("Error:", e)
