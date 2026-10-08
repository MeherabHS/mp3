package com.hifi.flutter_app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/**
 * Thin wrapper around youtubedl-android (yt-dlp on Android).
 * Inspired by YTDLnis — same library, simplified for audio-only downloads.
 */
object YtDlpHelper {

    private const val TAG = "YtDlpHelper"
    private var initialized = false

    // ── Init ──────────────────────────────────────────────────────────────────

    /** Initialize yt-dlp + FFmpeg. Safe to call multiple times. */
    suspend fun init(context: Context) = withContext(Dispatchers.IO) {
        if (initialized) return@withContext
        try {
            YoutubeDL.getInstance().init(context)
            FFmpeg.getInstance().init(context)
            initialized = true
            Log.i(TAG, "yt-dlp initialized OK")
        } catch (e: Exception) {
            Log.e(TAG, "Init failed: ${e.message}")
        }
    }

    /** Update yt-dlp binary from GitHub. Call once per day at most. */
    suspend fun update(context: Context): Boolean = withContext(Dispatchers.IO) {
        try {
            val status = YoutubeDL.getInstance().updateYoutubeDL(context)
            status == YoutubeDL.UpdateStatus.DONE
        } catch (e: Exception) {
            Log.w(TAG, "Update failed: ${e.message}")
            false
        }
    }

    // ── Download ──────────────────────────────────────────────────────────────

    /**
     * Download the best audio stream from [url] into [outputDir].
     * Returns the absolute path of the resulting file, or null on failure.
     *
     * Uses directory-scan to locate the output file — this is more reliable than
     * parsing stdout because FFmpeg post-processing can rename the file after download.
     */
    suspend fun downloadAudio(
        url: String,
        outputDir: File,
        onProgress: (Float, Long, String) -> Unit = { _, _, _ -> },
    ): String? = withContext(Dispatchers.IO) {

        // Retry init in case startup init failed (e.g. no network at boot)
        if (!initialized) init(outputDir.context())
        if (!initialized) {
            Log.e(TAG, "Cannot download — yt-dlp not initialized")
            return@withContext null
        }

        outputDir.mkdirs()

        // Snapshot existing files so we can find the new one after download
        val before = outputDir.listFiles()?.map { it.absolutePath }?.toSet() ?: emptySet()

        val request = YoutubeDLRequest(url).apply {
            // Prefer m4a/aac — widest Android compatibility. Opus/webm as fallback.
            addOption("-f", "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio/best")
            addOption("-o", "${outputDir.absolutePath}/%(title)s.%(ext)s")
            // Single video only
            addOption("--no-playlist")
            // Skip any post-processing that could silently delete the file
            // (thumbnail embed needs mutagen/AP which is NOT bundled → causes "no file")
            // (metadata embed via FFmpeg is safe but skipped here to keep the fallback minimal)
            // Network resilience
            addOption("--retries", "5")
            addOption("--fragment-retries", "5")
            addOption("--ignore-errors")
            addOption("--no-overwrites")
            // Bypass age-gate and geo-block where possible
            addOption("--age-limit", "99")
            // Spoof browser user-agent to reduce bot-detection
            addOption("--add-header", "User-Agent:Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36")
        }

        return@withContext try {
            YoutubeDL.getInstance().execute(request, null) { progress, eta, line ->
                onProgress(progress, eta, line)
            }

            // Find whichever new file appeared in outputDir
            val after = outputDir.listFiles()?.map { it.absolutePath }?.toSet() ?: emptySet()
            val newFiles = (after - before).filter { path ->
                val f = File(path)
                f.exists() && f.length() > 8192
            }

            if (newFiles.isEmpty()) {
                Log.w(TAG, "Download finished but no new file found in $outputDir")
                null
            } else {
                // If multiple new files, prefer the audio one (opus/m4a/ogg/wav)
                val audioExts = setOf("opus", "m4a", "ogg", "wav", "aac", "flac", "mp3", "webm")
                val picked = newFiles.firstOrNull { p ->
                    p.substringAfterLast('.').lowercase() in audioExts
                } ?: newFiles.first()
                Log.i(TAG, "Downloaded: $picked")
                picked
            }
        } catch (e: Exception) {
            Log.e(TAG, "Download failed: ${e.message}")
            null
        }
    }

    // ── Metadata probe ────────────────────────────────────────────────────────

    /**
     * Fetch title, uploader, duration via yt-dlp --dump-json (no download).
     * Returns a map with keys: title, artist, duration, thumbnail.
     */
    suspend fun fetchMetadata(url: String): Map<String, String> = withContext(Dispatchers.IO) {
        if (!initialized) return@withContext emptyMap()

        val request = YoutubeDLRequest(url).apply {
            addOption("--dump-json")
            addOption("--no-playlist")
            // Skip the slow signature-extraction step; we only need info
            addOption("--skip-download")
        }

        return@withContext try {
            // --dump-json writes the JSON object to stdout; read it from response.out
            val response = YoutubeDL.getInstance().execute(request, null, null)
            parseMetadataJson(response.out.trim())
        } catch (e: Exception) {
            Log.w(TAG, "fetchMetadata failed: ${e.message}")
            emptyMap()
        }
    }

    private fun parseMetadataJson(json: String): Map<String, String> {
        if (json.isBlank()) return emptyMap()
        // --dump-json may prefix status lines; find the JSON object
        val jsonStart = json.indexOf('{')
        val jsonEnd   = json.lastIndexOf('}')
        if (jsonStart < 0 || jsonEnd < 0) return emptyMap()
        return try {
            val obj = JSONObject(json.substring(jsonStart, jsonEnd + 1))
            mapOf(
                "title"     to obj.optString("title"),
                "artist"    to (obj.optString("artist").ifBlank { obj.optString("uploader") }),
                "album"     to obj.optString("album"),
                "thumbnail" to obj.optString("thumbnail"),
                "duration"  to obj.optInt("duration", 0).toString()
            )
        } catch (e: Exception) {
            emptyMap()
        }
    }

    // ── Auto-update ───────────────────────────────────────────────────────────

    /**
     * Update yt-dlp at most once per day. Safe to call on every launch;
     * it's a no-op if the update already ran within the last 24 hours.
     */
    suspend fun maybeAutoUpdate(context: Context) = withContext(Dispatchers.IO) {
        val prefs: SharedPreferences =
            context.getSharedPreferences("ytdlp_prefs", Context.MODE_PRIVATE)
        val lastUpdate = prefs.getLong("last_update_ms", 0L)
        val oneDayMs   = 24L * 60 * 60 * 1000
        if (System.currentTimeMillis() - lastUpdate < oneDayMs) return@withContext
        try {
            val status = YoutubeDL.getInstance().updateYoutubeDL(context)
            if (status == YoutubeDL.UpdateStatus.DONE) {
                prefs.edit().putLong("last_update_ms", System.currentTimeMillis()).apply()
                Log.i(TAG, "yt-dlp binary updated successfully")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Auto-update failed (non-fatal): ${e.message}")
        }
    }

    // ── Context storage ───────────────────────────────────────────────────────
    // We store the application context when first init is called from MainActivity.
    private var appContext: Context? = null
    fun storeContext(ctx: Context) { appContext = ctx.applicationContext }
    private fun File.context(): Context = appContext
        ?: throw IllegalStateException("YtDlpHelper not initialized with context")
}
