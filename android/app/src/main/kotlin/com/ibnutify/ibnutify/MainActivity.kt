package com.ibnutify.ibnutify

import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlin.concurrent.thread
import kotlin.system.exitProcess

class MainActivity: AudioServiceFragmentActivity() {
    private val CHANNEL = "com.ibnutify.ml/audio"

    // [BUG-5 FIX] Explicit PARTIAL_WAKE_LOCK untuk Workout GPS background tracking.
    private var wakeLock: PowerManager.WakeLock? = null

    // [F2-4 FIX] MethodChannel reference untuk closeAppDeeper
    private var methodChannel: MethodChannel? = null

    // ─── [F2-5 FIX] BroadcastReceiver untuk ACTION_AUDIO_BECOMING_NOISY ────────────
    // Dipanggil Android saat perangkat audio nirkabel (TWS/headphone) terputus.
    // Tanpa ini, AudioPlayer melanjutkan pemutaran lewat speaker secara otomatis.
    private var noisyReceiverRegistered = false
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                android.util.Log.d("IbnuTify", "[F2-5] ACTION_AUDIO_BECOMING_NOISY fired — forcing pause")
                // Kirim command pause ke Dart via MethodChannel agar PlayerNotifier.state sinkron
                Handler(Looper.getMainLooper()).post {
                    methodChannel?.invokeMethod("onAudioBecomingNoisy", null)
                }
            }
        }
    }

    private fun registerNoisyReceiver() {
        if (noisyReceiverRegistered) return
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        registerReceiver(noisyReceiver, filter)
        noisyReceiverRegistered = true
        android.util.Log.d("IbnuTify", "[F2-5] NoisyReceiver registered")
    }

    private fun unregisterNoisyReceiver() {
        if (!noisyReceiverRegistered) return
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        noisyReceiverRegistered = false
        android.util.Log.d("IbnuTify", "[F2-5] NoisyReceiver unregistered")
    }

    override fun onResume() {
        super.onResume()
        registerNoisyReceiver()
    }

    override fun onPause() {
        super.onPause()
        // Tetap registered saat di background agar TWS disconnect terdeteksi saat app background
        // JANGAN unregister di sini — cukup unregister di onDestroy
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        thread {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(this))
            }
        }

        // [F2-4+F2-5 FIX] Store channel reference for NoisyReceiver → Dart callbacks
        val mc = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = mc
        mc.setMethodCallHandler { call, result ->
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
                    val songIdArg = call.argument<Any>("songId")
                    val songId = when (songIdArg) {
                        is Number -> songIdArg.toLong()
                        is String -> songIdArg.toLongOrNull()
                        else -> null
                    }
                    val filePath = call.argument<String>("filePath")

                    thread {
                        try {
                            // 1. Hapus file fisik dari storage jika filePath ada
                            if (!filePath.isNullOrEmpty()) {
                                try {
                                    val file = java.io.File(filePath)
                                    if (file.exists()) {
                                        file.delete()
                                    }
                                } catch (_: Exception) {}
                            }

                            // 2. Hapus dari Android MediaStore ContentResolver jika songId ada
                            if (songId != null) {
                                try {
                                    val contentUri = ContentUris.withAppendedId(
                                        MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, songId
                                    )
                                    contentResolver.delete(contentUri, null, null)
                                } catch (_: Exception) {}
                            }

                            // 3. Informasikan Android MediaScanner bahwa file sudah terhapus
                            if (!filePath.isNullOrEmpty()) {
                                try {
                                    android.media.MediaScannerConnection.scanFile(
                                        applicationContext,
                                        arrayOf(filePath),
                                        null
                                    ) { _, _ -> }
                                } catch (_: Exception) {}
                            }

                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
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
                    val fallbackFfmpegPath = java.io.File(applicationContext.applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath
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
                                        applicationContext,
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

                "cancelDownload" -> {
                    thread {
                        try {
                            if (Python.isStarted()) {
                                val py = Python.getInstance()
                                val downloaderModule = py.getModule("downloader")
                                downloaderModule.callAttr("cancel_download")
                            }
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.error("CANCEL_ERROR", e.message, null)
                            }
                        }
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
                    val fallbackFfmpegPath = java.io.File(applicationContext.applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath
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
                                            applicationContext, paths, null
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

                // ── Workout WakeLock ─────────────────────────────────────────────────────────
                // [BUG-5 FIX] Dipanggil dari WorkoutNotifier.startWorkout() via MethodChannel
                "acquireWakeLock" -> {
                    try {
                        if (wakeLock == null || wakeLock?.isHeld == false) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            wakeLock = pm.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "IbnuTify::WorkoutWakeLock"
                            ).apply {
                                // Timeout 4 jam maksimum untuk safety (tidak bisa terlupa release)
                                acquire(4 * 60 * 60 * 1000L)
                            }
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }

                "releaseWakeLock" -> {
                    try {
                        if (wakeLock?.isHeld == true) {
                            wakeLock?.release()
                        }
                        wakeLock = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WAKELOCK_ERROR", e.message, null)
                    }
                }

                "openUrl" -> {
                    val url = call.argument<String>("url")
                    if (!url.isNullOrEmpty()) {
                        try {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("OPEN_URL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENT", "url is null", null)
                    }
                }

                // ── [F2-4 FIX] Force Close App (Sleep Timer & Curfew) ─────────────────────────
                // SystemNavigator.pop() tidak reliable di Release Mode — tidak mematikan
                // background MediaPlayback service. Gunakan finishAndRemoveTask() + exitProcess(0)
                // untuk memastikan app dan semua service benar-benar mati.
                "closeAppDeeper" -> {
                    try {
                        // 1. Stop audio playback dulu
                        try {
                            val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            am.abandonAudioFocus(null)
                        } catch (_: Exception) {}

                        // 2. Finish dan hapus dari Recents task
                        finishAndRemoveTask()

                        // 3. Kill proses secara paksa (300ms delay agar finishAndRemoveTask() sempat dieksekusi)
                        Handler(Looper.getMainLooper()).postDelayed({
                            exitProcess(0)
                        }, 300)

                        result.success(true)
                    } catch (e: Exception) {
                        // Fallback: paksa exit langsung
                        result.success(true)
                        exitProcess(0)
                    }
                }

                else -> result.notImplemented()

            }
        }
    }

    override fun onDestroy() {
        // Pastikan WakeLock dilepas saat Activity dihancurkan
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                wakeLock = null
            }
        } catch (_: Exception) {}

        // [F2-5 FIX] Unregister NoisyReceiver
        unregisterNoisyReceiver()

        super.onDestroy()
    }
}
