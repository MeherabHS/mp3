package com.hifi.flutter_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File

class MainActivity : FlutterActivity() {
    private val PLAYBACK_CHANNEL    = "com.hifi.musicplayer/playback"
    private val OUTPUT_CHANNEL      = "com.hifi.musicplayer/output"
    private val PERMISSION_CHANNEL  = "com.hifi.musicplayer/permissions"
    private val EQ_CHANNEL          = "com.hifi.musicplayer/equalizer"
    private val YTDLP_CHANNEL       = "com.hifi.musicplayer/ytdlp"
    private val STORAGE_PERM_CODE   = 1001

    private var audioOutputDetector: AudioOutputDetector? = null
    private var playbackChannel: MethodChannel? = null
    private var outputChannel: MethodChannel? = null
    private var permChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Request storage permissions on startup
        requestStoragePermissions()

        // Start playback service
        startService(Intent(this, PlaybackService::class.java))

        // Initialize yt-dlp in background, then auto-update binary if >24 h old.
        YtDlpHelper.storeContext(applicationContext)
        CoroutineScope(Dispatchers.IO).launch {
            YtDlpHelper.init(applicationContext)
            YtDlpHelper.maybeAutoUpdate(applicationContext)
        }

        // Setup permissions & storage discovery channel
        permChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL)
        permChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestStoragePermissions" -> {
                    requestStoragePermissions()
                    result.success(true)
                }
                "hasStoragePermissions" -> {
                    result.success(hasStoragePermissions())
                }
                "getMediaStoreAudioPaths" -> {
                    result.success(getMediaStoreAudioPaths())
                }
                "getMountedStoragePaths" -> {
                    result.success(getMountedStoragePaths())
                }
                else -> result.notImplemented()
            }
        }

        // Setup playback method channel
        playbackChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLAYBACK_CHANNEL)
        PlaybackService.methodChannel = playbackChannel

        playbackChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "playFile" -> {
                    val path = call.argument<String>("path") ?: return@setMethodCallHandler result.error("MISSING_ARG", "path required", null)
                    val title = call.argument<String>("title")
                    val artist = call.argument<String>("artist")
                    val album = call.argument<String>("album")
                    val artworkPath = call.argument<String>("artworkPath")
                    PlaybackService.playFile(path, title, artist, album, artworkPath)
                    result.success(true)
                }
                "setQueueAndPlay" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val startIndex = call.argument<Int>("startIndex") ?: 0
                    PlaybackService.setQueueAndPlay(paths, startIndex)
                    result.success(true)
                }
                "pause" -> {
                    PlaybackService.pausePlayback()
                    result.success(true)
                }
                "resume" -> {
                    PlaybackService.resumePlayback()
                    result.success(true)
                }
                "seekTo" -> {
                    val posMs = call.argument<Long>("positionMs") ?: 0L
                    PlaybackService.seekTo(posMs)
                    result.success(true)
                }
                "next" -> {
                    PlaybackService.skipToNext()
                    result.success(true)
                }
                "previous" -> {
                    PlaybackService.skipToPrevious()
                    result.success(true)
                }
                "getPosition" -> {
                    result.success(PlaybackService.getCurrentPositionMs())
                }
                "getDuration" -> {
                    result.success(PlaybackService.getDurationMs())
                }
                "isPlaying" -> {
                    result.success(PlaybackService.isPlaying())
                }
                else -> result.notImplemented()
            }
        }

        // Setup output (Bluetooth / DAC) method channel
        outputChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OUTPUT_CHANNEL)
        outputChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentOutput" -> {
                    val outputJson = audioOutputDetector?.getCurrentOutputJson()
                    result.success(outputJson?.toString() ?: "{}")
                }
                else -> result.notImplemented()
            }
        }

        audioOutputDetector = AudioOutputDetector(this) { json ->
            runOnUiThread {
                outputChannel?.invokeMethod("onOutputChanged", json.toString())
            }
        }
        audioOutputDetector?.start()

        // Setup equalizer channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EQ_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "applyEqualizer" -> {
                        val gainsMb = call.argument<List<Int>>("gainsMb") ?: List(7) { 0 }
                        val enabled = call.argument<Boolean>("enabled") ?: true
                        PlaybackService.applyEqualizer(gainsMb, enabled)
                        result.success(true)
                    }
                    "applyEnhancements" -> {
                        val bass = call.argument<Int>("bassStrength") ?: 0
                        val stereo = call.argument<Int>("stereoWidth") ?: 0
                        val loudness = call.argument<Int>("loudnessMb") ?: 0
                        PlaybackService.applyEnhancements(bass, stereo, loudness)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── yt-dlp download channel ──────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, YTDLP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "downloadAudio" -> {
                        val url = call.argument<String>("url")
                            ?: return@setMethodCallHandler result.error("MISSING_ARG", "url required", null)
                        val outputDir = call.argument<String>("outputDir")
                            ?: getExternalFilesDir(null)?.absolutePath
                            ?: filesDir.absolutePath

                        CoroutineScope(Dispatchers.IO).launch {
                            val filePath = YtDlpHelper.downloadAudio(
                                url = url,
                                outputDir = File(outputDir),
                            )
                            runOnUiThread {
                                if (filePath != null) result.success(filePath)
                                else result.error("DOWNLOAD_FAILED", "yt-dlp returned no file", null)
                            }
                        }
                    }

                    "fetchMetadata" -> {
                        val url = call.argument<String>("url")
                            ?: return@setMethodCallHandler result.error("MISSING_ARG", "url required", null)

                        CoroutineScope(Dispatchers.IO).launch {
                            val meta = YtDlpHelper.fetchMetadata(url)
                            runOnUiThread { result.success(meta) }
                        }
                    }

                    "updateYtDlp" -> {
                        CoroutineScope(Dispatchers.IO).launch {
                            val ok = YtDlpHelper.update(applicationContext)
                            runOnUiThread { result.success(ok) }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun getMediaStoreAudioPaths(): List<String> {
        val audioList = mutableListOf<String>()
        val seen = mutableSetOf<String>()

        // Music-only containers — deliberately excludes mp4/webm (video containers)
        val supportedExts = setOf("mp3", "flac", "wav", "m4a", "ogg", "opus", "alac", "aac")

        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.DURATION,
        )

        // Only EXTERNAL — INTERNAL_CONTENT_URI returns system ringtones/UI sounds.
        // No IS_MUSIC filter so Downloads/Audiobooks/Podcasts are included too.
        // Duration >= 30 s filters out ringtones, notification sounds, and SFX.
        val selection = "${MediaStore.Audio.Media.DURATION} >= 30000"

        try {
            contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection, selection, null, null
            )?.use { cursor ->
                val dataIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DATA)
                val nameIdx = cursor.getColumnIndex(MediaStore.Audio.Media.DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val path = (if (dataIdx >= 0) cursor.getString(dataIdx) else null)
                        ?: continue
                    val name = if (nameIdx >= 0) cursor.getString(nameIdx) else null
                    val ext = (name ?: path).substringAfterLast('.', "").lowercase().trim()
                    if (ext in supportedExts && path !in seen && File(path).exists()) {
                        seen.add(path)
                        audioList.add(path)
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "MediaStore query failed: ${e.message}")
        }

        android.util.Log.i("MainActivity", "MediaStore found ${audioList.size} audio files")
        return audioList
    }

    private fun getMountedStoragePaths(): List<String> {
        val paths = mutableListOf<String>()
        paths.add("/storage/emulated/0")

        try {
            val dirs = ContextCompat.getExternalFilesDirs(this, null)
            for (dir in dirs) {
                if (dir != null) {
                    val fullPath = dir.absolutePath
                    val match = Regex("^(/storage/[^/]+)").find(fullPath)
                    if (match != null) {
                        val root = match.value
                        if (!paths.contains(root)) {
                            paths.add(root)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        try {
            val storageDir = File("/storage")
            if (storageDir.exists() && storageDir.isDirectory) {
                storageDir.listFiles()?.forEach { file ->
                    if (file.isDirectory && file.name != "emulated" && file.name != "self" && file.name != "knox") {
                        val p = file.absolutePath
                        if (!paths.contains(p)) {
                            paths.add(p)
                        }
                    }
                }
            }
        } catch (_: Exception) {}

        return paths
    }

    private fun hasStoragePermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStoragePermissions() {
        val permissionsList = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissionsList.add(Manifest.permission.READ_MEDIA_AUDIO)
            permissionsList.add(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            permissionsList.add(Manifest.permission.READ_EXTERNAL_STORAGE)
            permissionsList.add(Manifest.permission.WRITE_EXTERNAL_STORAGE)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissionsList.add(Manifest.permission.BLUETOOTH_CONNECT)
        }

        val needed = permissionsList.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (needed.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), STORAGE_PERM_CODE)
        }
    }

    override fun onDestroy() {
        audioOutputDetector?.stop()
        PlaybackService.methodChannel = null
        super.onDestroy()
    }
}
