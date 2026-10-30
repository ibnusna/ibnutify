=========================================
Starting download process for Spotify URL: https://open.spotify.com/track/1NuvCcuRUGN54bkSLk51LC?si=q3MD6LHySQWrkIsyGLAu0A&utm_source=copy-link
Download directory: /storage/emulated/0/Download/Ibnutify
Passed FFmpeg path: /data/app/~~MGbv29BEKAbgwKnKnirV8Q==/com.ibnutify.ibnutify-YM2x0sANOmuiZZpHhpoXRQ==/lib/arm64/libffmpeg.so
Step 1: Scrape Spotify metadata...
Extracted track ID: 1NuvCcuRUGN54bkSLk51LC
Spotify metadata scraped successfully:
  Title: Melompat Lebih Tinggi
  Artist: Lomba Sihir
  Album: Unknown Album
  Year: 2026
  Cover URL: https://image-cdn-ak.spotifycdn.com/image/ab67616d0000b273566dc9e464e2daa1b8b542ec
Step 2: Scrape iTunes metadata helper...
  iTunes Genre: Pop
  iTunes Album: Melompat Lebih Tinggi - Single
Step 3: Fetch lyrics from LRCLIB...
  Lyrics found.
  Synced lyrics (.lrc format) found.
Target output folder: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single
  Created target directory.
FFmpeg configuration:
  FFmpeg path: /data/app/~~MGbv29BEKAbgwKnKnirV8Q==/com.ibnutify.ibnutify-YM2x0sANOmuiZZpHhpoXRQ==/lib/arm64/libffmpeg.so
  FFmpeg exists: True
  use_ffmpeg: True
  Expected extension: mp3
  Target filepath: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp3
Checking if file already exists in download folder...
Step 4: Configure yt-dlp options...
Smart Search: Target duration is 221.0s. Searching top 10 results...
Smart Search: Found best match https://www.youtube.com/watch?v=wxHpJq5P4BM with duration diff 0.0s.
Configuring yt-dlp with FFmpeg integration for MP3 audio extraction.
Step 5: Run yt-dlp YoutubeDL.extract_info (attempt 1/3)
[WARNING] Deprecated Feature: Support for Python version 3.10 has been deprecated. Please update to Python 3.11 or above
[ERROR] Deprecated Feature: Support for Python version 3.10 has been deprecated. Please update to Python 3.11 or above
[DEBUG] [youtube] Extracting URL: https://www.youtube.com/watch?v=wxHpJq5P4BM
[DEBUG] [youtube] wxHpJq5P4BM: Downloading webpage
[DEBUG] [youtube] wxHpJq5P4BM: Downloading android player API JSON
[WARNING] [youtube] wxHpJq5P4BM: Some android client https formats have been skipped as they are missing a URL. YouTube may have enabled the SABR-only streaming experiment for the current session. See  https://github.com/yt-dlp/yt-dlp/issues/12482  for more details
[DEBUG] [info] wxHpJq5P4BM: Downloading 1 format(s): 18
[DEBUG] [info] Downloading video thumbnail 41 ...
[DEBUG] [info] Writing video thumbnail 41 to: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.webp
[DEBUG] [download] Destination: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp4
yt-dlp download finished, starting audio post-processing...
[DEBUG] [ExtractAudio] Destination: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp3
[DEBUG] Deleting original file /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp4 (pass -k to keep)
[DEBUG] [ThumbnailsConvertor] Converting thumbnail "/storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.webp" to png
[ERROR] ERROR: Postprocessing: Decoder (codec webp) not found for input stream #0:0
[WARNING] yt-dlp attempt 1/3 failed: ERROR: Postprocessing: Decoder (codec webp) not found for input stream #0:0
Traceback (most recent call last):
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3666, in process_info
    replace_info_dict(self.post_process(dl_filename, info_dict, files_to_move))
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3852, in post_process
    info = self.run_all_pps('post_process', info, additional_pps=info.get('__postprocessors'))
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3834, in run_all_pps
    info = self.run_pp(pp, info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3812, in run_pp
    files_to_delete, infodict = pp.run(infodict)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/common.py", line 23, in run
    ret = func(self, info, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/common.py", line 128, in wrapper
    return func(self, info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/embedthumbnail.py", line 84, in run
    thumbnail_filename = convertor.convert_thumbnail(thumbnail_filename, 'png')
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/ffmpeg.py", line 1098, in convert_thumbnail
    self.real_run_ffmpeg(
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/ffmpeg.py", line 360, in real_run_ffmpeg
    raise FFmpegPostProcessorError(stderr.strip().splitlines()[-1])
yt_dlp.postprocessor.ffmpeg.FFmpegPostProcessorError: Decoder (codec webp) not found for input stream #0:0

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/app/downloader.py", line 553, in download_track
    info = ydl.extract_info(best_youtube_url, download=True)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1720, in extract_info
    return self.__extract_info(url, self.get_info_extractor(key), download, extra_info, process)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1731, in wrapper
    return func(self, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1887, in __extract_info
    return self.process_ie_result(ie_result, download, extra_info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1946, in process_ie_result
    ie_result = self.process_video_result(ie_result, download=download)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3134, in process_video_result
    self.process_info(new_info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 194, in wrapper
    return func(self, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3668, in process_info
    self.report_error(f'Postprocessing: {err}')
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1165, in report_error
    self.trouble(f'{self._format_err("ERROR:", self.Styles.ERROR)} {message}', *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1103, in trouble
    raise DownloadError(message, exc_info)
yt_dlp.utils.DownloadError: ERROR: Postprocessing: Decoder (codec webp) not found for input stream #0:0

[Retry] Waiting 2s before next attempt...
Step 5: Run yt-dlp YoutubeDL.extract_info (attempt 2/3)
[Retry] Switching player_client order to: ios, android, web
[WARNING] Deprecated Feature: Support for Python version 3.10 has been deprecated. Please update to Python 3.11 or above
[ERROR] Deprecated Feature: Support for Python version 3.10 has been deprecated. Please update to Python 3.11 or above
[DEBUG] [youtube] Extracting URL: https://www.youtube.com/watch?v=wxHpJq5P4BM
[DEBUG] [youtube] wxHpJq5P4BM: Downloading webpage
[DEBUG] [youtube] wxHpJq5P4BM: Downloading ios player API JSON
[DEBUG] [youtube] wxHpJq5P4BM: Downloading android player API JSON
[WARNING] [youtube] wxHpJq5P4BM: Some ios client https formats have been skipped as they are missing a URL. YouTube may have enabled the SABR-only streaming experiment for the current session. See  https://github.com/yt-dlp/yt-dlp/issues/12482  for more details
[WARNING] [youtube] wxHpJq5P4BM: Some android client https formats have been skipped as they are missing a URL. YouTube may have enabled the SABR-only streaming experiment for the current session. See  https://github.com/yt-dlp/yt-dlp/issues/12482  for more details
[DEBUG] [info] wxHpJq5P4BM: Downloading 1 format(s): 18
[DEBUG] Deleting existing file /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.webp
[DEBUG] [info] Downloading video thumbnail 41 ...
[DEBUG] [info] Writing video thumbnail 41 to: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.webp
[DEBUG] [download] Destination: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp4
yt-dlp download finished, starting audio post-processing...
[DEBUG] [ExtractAudio] Destination: /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp3
[DEBUG] Deleting original file /storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.mp4 (pass -k to keep)
[DEBUG] [ThumbnailsConvertor] Converting thumbnail "/storage/emulated/0/Download/Ibnutify/Melompat Lebih Tinggi - Single/Melompat Lebih Tinggi.webp" to png
[ERROR] ERROR: Postprocessing: Decoder (codec webp) not found for input stream #0:0
[WARNING] yt-dlp attempt 2/3 failed: ERROR: Postprocessing: Decoder (codec webp) not found for input stream #0:0
Traceback (most recent call last):
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3666, in process_info
    replace_info_dict(self.post_process(dl_filename, info_dict, files_to_move))
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3852, in post_process
    info = self.run_all_pps('post_process', info, additional_pps=info.get('__postprocessors'))
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3834, in run_all_pps
    info = self.run_pp(pp, info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3812, in run_pp
    files_to_delete, infodict = pp.run(infodict)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/common.py", line 23, in run
    ret = func(self, info, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/common.py", line 128, in wrapper
    return func(self, info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/embedthumbnail.py", line 84, in run
    thumbnail_filename = convertor.convert_thumbnail(thumbnail_filename, 'png')
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/ffmpeg.py", line 1098, in convert_thumbnail
    self.real_run_ffmpeg(
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/postprocessor/ffmpeg.py", line 360, in real_run_ffmpeg
    raise FFmpegPostProcessorError(stderr.strip().splitlines()[-1])
yt_dlp.postprocessor.ffmpeg.FFmpegPostProcessorError: Decoder (codec webp) not found for input stream #0:0

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/app/downloader.py", line 553, in download_track
    info = ydl.extract_info(best_youtube_url, download=True)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1720, in extract_info
    return self.__extract_info(url, self.get_info_extractor(key), download, extra_info, process)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1731, in wrapper
    return func(self, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1887, in __extract_info
    return self.process_ie_result(ie_result, download, extra_info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1946, in process_ie_result
    ie_result = self.process_video_result(ie_result, download=download)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3134, in process_video_result
    self.process_info(new_info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 194, in wrapper
    return func(self, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3668, in process_info
    self.report_error(f'Postprocessing: {err}')
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1165, in report_error
    self.trouble(f'{self._format_err("ERROR:", self.Styles.ERROR)} {message}', *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1103, in trouble
    raise DownloadError(message, exc_info)
yt_dlp.utils.DownloadError: ERROR: Postprocessing: Decoder (codec webp) not found for input stream #0:0

[Retry] Waiting 4s before next attempt...
Step 5: Run yt-dlp YoutubeDL.extract_info (attempt 3/3)
[Retry] Switching player_client order to: tv_embedded, web
[WARNING] Deprecated Feature: Support for Python version 3.10 has been deprecated. Please update to Python 3.11 or above
[ERROR] Deprecated Feature: Support for Python version 3.10 has been deprecated. Please update to Python 3.11 or above
[DEBUG] [youtube] Extracting URL: https://www.youtube.com/watch?v=wxHpJq5P4BM
[DEBUG] [youtube] wxHpJq5P4BM: Downloading webpage
[WARNING] [youtube] Skipping unsupported client "tv_embedded"
[WARNING] Only images are available for download. use --list-formats to see them
[ERROR] ERROR: [youtube] wxHpJq5P4BM: Requested format is not available. Use --list-formats for a list of available formats
[WARNING] yt-dlp attempt 3/3 failed: ERROR: [youtube] wxHpJq5P4BM: Requested format is not available. Use --list-formats for a list of available formats
Traceback (most recent call last):
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1731, in wrapper
    return func(self, *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1887, in __extract_info
    return self.process_ie_result(ie_result, download, extra_info)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1946, in process_ie_result
    ie_result = self.process_video_result(ie_result, download=download)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 3096, in process_video_result
    raise ExtractorError(
yt_dlp.utils.ExtractorError: [youtube] wxHpJq5P4BM: Requested format is not available. Use --list-formats for a list of available formats

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/app/downloader.py", line 553, in download_track
    info = ydl.extract_info(best_youtube_url, download=True)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1720, in extract_info
    return self.__extract_info(url, self.get_info_extractor(key), download, extra_info, process)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1749, in wrapper
    self.report_error(str(e), e.format_traceback())
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1165, in report_error
    self.trouble(f'{self._format_err("ERROR:", self.Styles.ERROR)} {message}', *args, **kwargs)
  File "/data/data/com.ibnutify.ibnutify/files/chaquopy/AssetFinder/requirements/yt_dlp/YoutubeDL.py", line 1103, in trouble
    raise DownloadError(message, exc_info)
yt_dlp.utils.DownloadError: ERROR: [youtube] wxHpJq5P4BM: Requested format is not available. Use --list-formats for a list of available formats

[ERROR] All 3 yt-dlp attempts failed.
Download gagal setelah 3 percobaan: ERROR: [youtube] wxHpJq5P4BM: Requested format is not available. Use --list-formats for a list of available formats
