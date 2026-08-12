import yt_dlp

target_duration = 271.477

ydl_opts = {
    'quiet': True,
    'extract_flat': True,
}
with yt_dlp.YoutubeDL(ydl_opts) as ydl:
    info = ydl.extract_info("ytsearch10:Sal Priadi Foto kita blur MV", download=False)
    entries = info.get('entries', [])
    print("Youtube Results:")
    best_entry = None
    min_diff = 9999
    
    for e in entries:
        dur = e.get('duration')
        title = e.get('title')
        url = e.get('url')
        if not dur: continue
        diff = abs(dur - target_duration)
        print(f"- {dur}s (diff {diff:.1f}s) : {title} ({url})")
        if diff < min_diff:
            min_diff = diff
            best_entry = e
            
    print(f"\nBEST MATCH: {best_entry['title']} ({best_entry['url']}) with diff {min_diff:.1f}s")
