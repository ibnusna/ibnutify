package com.ibnutify.ibnutify

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.ibnutify.ml/audio"

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return AudioServicePlugin.getFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        thread {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(this))
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractFeatures" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        thread {
                            try {
                                // Ensure Python is started before calling
                                while (!Python.isStarted()) {
                                    Thread.sleep(100)
                                }
                                val py = Python.getInstance()
                                val analyzerModule = py.getModule("analyzer")
                                
                                val res = analyzerModule.callAttr("extract_features", filePath).toString()
                                Handler(Looper.getMainLooper()).post {
                                    result.success(res)
                                }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("PYTHON_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "filePath is null", null)
                    }
                }
                "clusterSongs" -> {
                    val featuresJson = call.argument<String>("featuresJson")
                    if (featuresJson != null) {
                        thread {
                            try {
                                while (!Python.isStarted()) {
                                    Thread.sleep(100)
                                }
                                val py = Python.getInstance()
                                val analyzerModule = py.getModule("analyzer")

                                val res = analyzerModule.callAttr("cluster_songs", featuresJson).toString()
                                Handler(Looper.getMainLooper()).post {
                                    result.success(res)
                                }
                            } catch (e: Exception) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("PYTHON_ERROR", e.message, null)
                                }
                            }
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "featuresJson is null", null)
                    }
                }
                "deleteSong" -> {
                    val songId = call.argument<Int>("songId")?.toLong()
                    if (songId == null) {
                        result.error("INVALID_ARGUMENT", "songId is null", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            val contentUri = ContentUris.withAppendedId(
                                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId
                            )
                            val deleted = contentResolver.delete(contentUri, null, null)
                            Handler(Looper.getMainLooper()).post {
                                if (deleted > 0) {
                                    result.success(true)
                                } else {
                                    result.error("DELETE_FAILED", "File not found or already deleted (id=$songId)", null)
                                }
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("DELETE_ERROR", e.message, null)
                            }
                        }
                    }
                }

                // ── Music Downloader ──────────────────────────────────────────────────────
                "downloadTrack" -> {
                    val spotifyUrl = call.argument<String>("spotifyUrl")
                    val downloadDir = call.argument<String>("downloadDir")
                    val fallbackFfmpegPath = java.io.File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath
                    val ffmpegPath = call.argument<String>("ffmpegPath")?.takeIf { it.isNotEmpty() } ?: fallbackFfmpegPath

                    if (spotifyUrl == null || downloadDir == null) {
                        result.error("INVALID_ARGUMENT", "spotifyUrl and downloadDir are required", null)
                        return@setMethodCallHandler
                    }

                    // Pastikan folder tujuan ada
                    try {
                        val dir = java.io.File(downloadDir)
                        if (!dir.exists()) dir.mkdirs()
                    } catch (_: Exception) {}

                    thread {
                        try {
                            while (!Python.isStarted()) { Thread.sleep(100) }
                            val py = Python.getInstance()
                            val downloaderModule = py.getModule("downloader")

                            val res = downloaderModule.callAttr(
                                "download_track", spotifyUrl, downloadDir, ffmpegPath
                            ).toString()

                            // Trigger MediaScanner scan so Android immediately detects the new music file
                            try {
                                val jsonObj = org.json.JSONObject(res)
                                val filePath = jsonObj.optString("file_path", "")
                                if (filePath.isNotEmpty()) {
                                    android.media.MediaScannerConnection.scanFile(
                                        context,
                                        arrayOf(filePath),
                                        null
                                    ) { _, _ -> }
                                }
                            } catch (_: Exception) {}

                            Handler(Looper.getMainLooper()).post {
                                result.success(res)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("DOWNLOAD_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "getDownloadProgress" -> {
                    // Tidak perlu background thread — hanya baca dict progress
                    try {
                        while (!Python.isStarted()) { Thread.sleep(50) }
                        val py = Python.getInstance()
                        val downloaderModule = py.getModule("downloader")
                        val res = downloaderModule.callAttr("get_download_progress").toString()
                        result.success(res)
                    } catch (e: Exception) {
                        result.error("PROGRESS_ERROR", e.message, null)
                    }
                }

                "getDownloadLog" -> {
                    try {
                        while (!Python.isStarted()) { Thread.sleep(50) }
                        val py = Python.getInstance()
                        val downloaderModule = py.getModule("downloader")
                        val res = downloaderModule.callAttr("get_download_log").toString()
                        result.success(res)
                    } catch (e: Exception) {
                        result.error("LOG_ERROR", e.message, null)
                    }
                }

                "getTrackMetadata" -> {
                    val spotifyUrl = call.argument<String>("spotifyUrl")
                    if (spotifyUrl == null) {
                        result.error("INVALID_ARGUMENT", "spotifyUrl is required", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            while (!Python.isStarted()) { Thread.sleep(100) }
                            val py = Python.getInstance()
                            val downloaderModule = py.getModule("downloader")
                            val res = downloaderModule.callAttr("get_track_metadata", spotifyUrl).toString()
                            Handler(Looper.getMainLooper()).post {
                                result.success(res)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("METADATA_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "getPlaylistTracks" -> {
                    val spotifyUrl = call.argument<String>("spotifyUrl")
                    if (spotifyUrl == null) {
                        result.error("INVALID_ARGUMENT", "spotifyUrl is required", null)
                        return@setMethodCallHandler
                    }
                    thread {
                        try {
                            while (!Python.isStarted()) { Thread.sleep(100) }
                            val py = Python.getInstance()
                            val downloaderModule = py.getModule("downloader")
                            val res = downloaderModule.callAttr("get_playlist_tracks", spotifyUrl).toString()
                            Handler(Looper.getMainLooper()).post {
                                result.success(res)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("PLAYLIST_TRACKS_ERROR", e.message, null)
                            }
                        }
                    }
                }

                "downloadPlaylist" -> {
                    val spotifyUrl = call.argument<String>("spotifyUrl")
                    val downloadDir = call.argument<String>("downloadDir")
                    val fallbackFfmpegPath = java.io.File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath
                    val ffmpegPath = call.argument<String>("ffmpegPath")?.takeIf { it.isNotEmpty() } ?: fallbackFfmpegPath

                    if (spotifyUrl == null || downloadDir == null) {
                        result.error("INVALID_ARGUMENT", "spotifyUrl and downloadDir are required", null)
                        return@setMethodCallHandler
                    }

                    // Pastikan folder root ada
                    try {
                        val dir = java.io.File(downloadDir)
                        if (!dir.exists()) dir.mkdirs()
                    } catch (_: Exception) {}

                    thread {
                        try {
                            while (!Python.isStarted()) { Thread.sleep(100) }
                            val py = Python.getInstance()
                            val downloaderModule = py.getModule("downloader")

                            val res = downloaderModule.callAttr(
                                "download_playlist", spotifyUrl, downloadDir, ffmpegPath
                            ).toString()

                            // Scan semua file audio di subfolder playlist agar MediaStore mengenali file baru
                            try {
                                val jsonObj = org.json.JSONObject(res)
                                val playlistFolder = jsonObj.optString("playlist_folder", "")
                                if (playlistFolder.isNotEmpty()) {
                                    val folder = java.io.File(playlistFolder)
                                    val audioFiles = folder.listFiles { f ->
                                        f.isFile && (f.name.endsWith(".mp3") || f.name.endsWith(".m4a"))
                                    }
                                    if (!audioFiles.isNullOrEmpty()) {
                                        val paths = audioFiles.map { it.absolutePath }.toTypedArray()
                                        android.media.MediaScannerConnection.scanFile(
                                            context, paths, null
                                        ) { _, _ -> }
                                    }
                                }
                            } catch (_: Exception) {}

                            Handler(Looper.getMainLooper()).post {
                                result.success(res)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("DOWNLOAD_PLAYLIST_ERROR", e.message, null)
                            }
                        }
                    }
                }

                else -> result.notImplemented()

            }
        }
    }
}
