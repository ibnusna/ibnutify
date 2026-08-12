import yt_dlp

ydl_opts = {
    'quiet': True,
    'extract_flat': True,
}
with yt_dlp.YoutubeDL(ydl_opts) as ydl:
    info = ydl.extract_info("ytsearch5:Sal Priadi Foto kita blur", download=False)
    entries = info.get('entries', [])
    print("Youtube Results:")
    for e in entries:
        dur = e.get('duration')
        title = e.get('title')
        url = e.get('url')
        print(f"- {dur}s : {title} ({url})")
