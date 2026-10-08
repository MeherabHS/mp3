package com.hifi.flutter_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import androidx.annotation.OptIn
import androidx.core.app.NotificationCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.MediaStyleNotificationHelper
import io.flutter.plugin.common.MethodChannel
import java.io.File

class PlaybackService : MediaSessionService() {
    private var mediaSession: MediaSession? = null
    private var player: ExoPlayer? = null
    private var currentArtworkBitmap: Bitmap? = null

    // ── DSP Effects ───────────────────────────────────────────────────────────
    private var equalizer: android.media.audiofx.Equalizer? = null
    private var equalizerEnabled = true
    private val equalizerGainsMb = IntArray(7) { 0 }

    private var bassBoost: android.media.audiofx.BassBoost? = null
    private var bassBoostStrength: Short = 0          // 0–1000

    private var virtualizer: android.media.audiofx.Virtualizer? = null
    private var virtualizerStrength: Short = 0        // 0–1000

    private var loudnessEnhancer: android.media.audiofx.LoudnessEnhancer? = null
    private var loudnessTargetGainMb: Int = 0         // millibels, 0–600

    companion object {
        var methodChannel: MethodChannel? = null
        private var instance: PlaybackService? = null
        private const val CHANNEL_ID = "hifi_playback_channel"
        private const val NOTIFICATION_ID = 1001

        const val ACTION_PLAY = "com.hifi.musicplayer.ACTION_PLAY"
        const val ACTION_PAUSE = "com.hifi.musicplayer.ACTION_PAUSE"
        const val ACTION_NEXT = "com.hifi.musicplayer.ACTION_NEXT"
        const val ACTION_PREV = "com.hifi.musicplayer.ACTION_PREV"

        fun getInstance(): PlaybackService? = instance

        fun playFile(
            path: String,
            title: String? = null,
            artist: String? = null,
            album: String? = null,
            artworkPath: String? = null
        ) {
            instance?.playFileInternal(path, title, artist, album, artworkPath)
        }

        fun pausePlayback() {
            instance?.player?.pause()
        }

        fun resumePlayback() {
            instance?.player?.play()
        }

        fun seekTo(positionMs: Long) {
            instance?.player?.seekTo(positionMs)
        }

        fun skipToNext() {
            instance?.player?.seekToNextMediaItem()
        }

        fun skipToPrevious() {
            instance?.player?.seekToPreviousMediaItem()
        }

        fun setVolume(volume: Float) {
            instance?.player?.volume = volume.coerceIn(0f, 1f)
        }

        fun getCurrentPositionMs(): Long {
            return instance?.player?.currentPosition ?: 0L
        }

        fun getDurationMs(): Long {
            return instance?.player?.duration?.takeIf { it != C.TIME_UNSET } ?: 0L
        }

        fun isPlaying(): Boolean {
            return instance?.player?.isPlaying ?: false
        }

        fun setQueueAndPlay(paths: List<String>, startIndex: Int) {
            instance?.setQueueInternal(paths, startIndex)
        }

        fun applyEqualizer(gainsMb: List<Int>, enabled: Boolean) {
            instance?.applyEqualizerInternal(gainsMb, enabled)
        }

        /** Bass boost (0–1000), stereo width (0–1000), loudness gain in millibels (0–600). */
        fun applyEnhancements(bassStrength: Int, stereoWidth: Int, loudnessMb: Int) {
            instance?.applyEnhancementsInternal(bassStrength.toShort(), stereoWidth.toShort(), loudnessMb)
        }

        /** Called from position ticker to redraw the waveform progress bar. */
        @OptIn(UnstableApi::class)
        fun updateWaveformProgress(positionMs: Long, durationMs: Long) {
            val svc = instance ?: return
            val art = svc.currentArtworkBitmap ?: return
            val p = svc.player ?: return
            val fraction = if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
            val title = p.currentMediaItem?.mediaMetadata?.title
            val artist = p.currentMediaItem?.mediaMetadata?.artist
            svc.currentCompositeBitmap = svc.buildWaveformCompositeBitmap(art, title, artist, fraction)
            // Refresh notification so the progress bar moves
            svc.updateNotification()
        }
    }

    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        instance = this

        createNotificationChannel()

        val audioAttributes = AudioAttributes.Builder()
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .setUsage(C.USAGE_MEDIA)
            .setFlags(0)
            .build()

        player = ExoPlayer.Builder(this)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .build()

        player?.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                emitPlaybackState()
                updateNotification()
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                emitPlaybackState()
                updateNotification()
                if (playbackState == Player.STATE_READY && equalizer == null) {
                    initEqualizerForSession()
                }
                // STATE_ENDED only fires when the entire queue is exhausted.
                // Individual track transitions are handled by onMediaItemTransition.
                if (playbackState == Player.STATE_ENDED) {
                    methodChannel?.invokeMethod("onQueueEnded", null)
                }
            }

            // Fired by ExoPlayer whenever it moves to a different item in the
            // queue — this is what keeps the Flutter UI in sync on auto-advance.
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val index = player?.currentMediaItemIndex ?: return
                val dur = player?.duration?.takeIf { it != C.TIME_UNSET } ?: 0L
                methodChannel?.invokeMethod(
                    "onTrackChanged",
                    mapOf("queueIndex" to index, "durationMs" to dur)
                )
                emitPlaybackState()
                updateNotification()
            }
        })
        initEqualizerForSession()

        // Position ticker — emit position & duration every 250ms when playing
        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var waveformTickCounter = 0
        val positionRunnable = object : Runnable {
            override fun run() {
                val p = player
                if (p != null && p.isPlaying) {
                    val posMs = p.currentPosition
                    val durMs = p.duration.takeIf { it != C.TIME_UNSET && it > 0 } ?: 0L
                    methodChannel?.invokeMethod("onPositionChanged", mapOf(
                        "positionMs" to posMs,
                        "durationMs" to durMs
                    ))
                    // Redraw waveform progress bar every ~2 s (every 8 ticks × 250ms)
                    waveformTickCounter++
                    if (waveformTickCounter >= 8) {
                        waveformTickCounter = 0
                        updateWaveformProgress(posMs, durMs)
                    }
                }
                handler.postDelayed(this, 250)
            }
        }
        handler.post(positionRunnable)

        player?.let { p ->
            val sessionActivityIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this, 0, sessionActivityIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )

            mediaSession = MediaSession.Builder(this, p)
                .setSessionActivity(pendingIntent)
                .build()
        }
    }

    // ── Equalizer helpers ─────────────────────────────────────────────────────

    private fun initEqualizerForSession() {
        val sessionId = player?.audioSessionId ?: return
        if (sessionId == android.media.AudioManager.ERROR) return
        try {
            equalizer?.release()
            equalizer = android.media.audiofx.Equalizer(0, sessionId).also { eq ->
                eq.enabled = equalizerEnabled
                val bands = minOf(eq.numberOfBands.toInt(), equalizerGainsMb.size)
                for (i in 0 until bands) eq.setBandLevel(i.toShort(), equalizerGainsMb[i].toShort())
            }
        } catch (e: Exception) {
            android.util.Log.w("PlaybackService", "EQ init failed: ${e.message}")
        }
        try {
            bassBoost?.release()
            bassBoost = android.media.audiofx.BassBoost(0, sessionId).also { bb ->
                bb.enabled = bassBoostStrength > 0
                if (bb.strengthSupported) bb.setStrength(bassBoostStrength)
            }
        } catch (e: Exception) {
            android.util.Log.w("PlaybackService", "BassBoost init failed: ${e.message}")
        }
        try {
            virtualizer?.release()
            virtualizer = android.media.audiofx.Virtualizer(0, sessionId).also { v ->
                v.enabled = virtualizerStrength > 0
                if (v.strengthSupported) v.setStrength(virtualizerStrength)
            }
        } catch (e: Exception) {
            android.util.Log.w("PlaybackService", "Virtualizer init failed: ${e.message}")
        }
        try {
            loudnessEnhancer?.release()
            loudnessEnhancer = android.media.audiofx.LoudnessEnhancer(sessionId).also { le ->
                le.enabled = loudnessTargetGainMb > 0
                le.setTargetGain(loudnessTargetGainMb)
            }
        } catch (e: Exception) {
            android.util.Log.w("PlaybackService", "LoudnessEnhancer init failed: ${e.message}")
        }
    }

    private fun applyEnhancementsInternal(bassStrength: Short, stereoWidth: Short, loudnessMb: Int) {
        bassBoostStrength = bassStrength
        virtualizerStrength = stereoWidth
        loudnessTargetGainMb = loudnessMb
        try {
            bassBoost?.let { bb ->
                bb.enabled = bassStrength > 0
                if (bb.strengthSupported) bb.setStrength(bassStrength)
            }
        } catch (e: Exception) { android.util.Log.w("PlaybackService", "BassBoost apply failed: ${e.message}") }
        try {
            virtualizer?.let { v ->
                v.enabled = stereoWidth > 0
                if (v.strengthSupported) v.setStrength(stereoWidth)
            }
        } catch (e: Exception) { android.util.Log.w("PlaybackService", "Virtualizer apply failed: ${e.message}") }
        try {
            loudnessEnhancer?.let { le ->
                le.enabled = loudnessMb > 0
                le.setTargetGain(loudnessMb)
            }
        } catch (e: Exception) { android.util.Log.w("PlaybackService", "LoudnessEnhancer apply failed: ${e.message}") }
    }

    private fun applyEqualizerInternal(gainsMb: List<Int>, enabled: Boolean) {
        equalizerEnabled = enabled
        gainsMb.forEachIndexed { i, v -> if (i < equalizerGainsMb.size) equalizerGainsMb[i] = v }
        try {
            val eq = equalizer ?: run { initEqualizerForSession(); equalizer } ?: return
            eq.enabled = enabled
            val bands = minOf(eq.numberOfBands.toInt(), gainsMb.size)
            for (i in 0 until bands) {
                eq.setBandLevel(i.toShort(), gainsMb[i].toShort())
            }
        } catch (e: Exception) {
            android.util.Log.w("PlaybackService", "EQ apply failed: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> player?.play()
            ACTION_PAUSE -> player?.pause()
            ACTION_NEXT -> skipToNext()
            ACTION_PREV -> skipToPrevious()
        }
        return super.onStartCommand(intent, flags, startId)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Personal Hi-Fi Playback",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows currently playing music controls with album art"
                setShowBadge(false)
                lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun playFileInternal(
        path: String,
        title: String? = null,
        artist: String? = null,
        album: String? = null,
        artworkPath: String? = null
    ) {
        val player = this.player ?: return
        val uri = Uri.fromFile(File(path))

        val metadataBuilder = MediaMetadata.Builder()
            .setTitle(title ?: File(path).nameWithoutExtension)
            .setArtist(artist ?: "Personal Hi-Fi")
            .setAlbumTitle(album ?: "")

        currentArtworkBitmap = null
        currentCompositeBitmap = null
        if (artworkPath != null && File(artworkPath).exists()) {
            try {
                val artFile = File(artworkPath)
                currentArtworkBitmap = BitmapFactory.decodeFile(artworkPath)

                // Build the waveform composite for lock screen + expanded notification
                val composite = buildWaveformCompositeBitmap(
                    currentArtworkBitmap, title, artist, 0f
                )
                currentCompositeBitmap = composite

                // Android 12+ lock-screen player reads METADATA_KEY_ART / artwork data
                // We embed the composite so the OS renders our waveform design on the lock screen.
                val compositeStream = java.io.ByteArrayOutputStream()
                composite.compress(Bitmap.CompressFormat.PNG, 90, compositeStream)
                metadataBuilder.setArtworkData(
                    compositeStream.toByteArray(),
                    MediaMetadata.PICTURE_TYPE_FRONT_COVER
                )
                metadataBuilder.setArtworkUri(Uri.fromFile(artFile))
            } catch (_: Exception) {}
        }

        val mediaItem = MediaItem.Builder()
            .setUri(uri)
            .setMediaMetadata(metadataBuilder.build())
            .build()

        player.setMediaItem(mediaItem)
        player.prepare()
        player.play()
        emitPlaybackState()
        updateNotification()
    }

    private fun setQueueInternal(paths: List<String>, startIndex: Int) {
        val player = this.player ?: return
        val items = paths.map { path ->
            val metadata = MediaMetadata.Builder()
                .setTitle(File(path).nameWithoutExtension)
                .setArtist("Personal Hi-Fi")
                .build()
            MediaItem.Builder()
                .setUri(Uri.fromFile(File(path)))
                .setMediaMetadata(metadata)
                .build()
        }
        player.setMediaItems(items, startIndex, 0L)
        player.prepare()
        player.play()
        emitPlaybackState()
        updateNotification()
    }

    @OptIn(UnstableApi::class)
    private fun updateNotification() {
        val session = mediaSession ?: return
        val p = player ?: return
        if (p.mediaItemCount == 0) return

        val currentItem = p.currentMediaItem
        val title = currentItem?.mediaMetadata?.title ?: "Personal Hi-Fi"
        val artist = currentItem?.mediaMetadata?.artist ?: "Playing Audio"
        val album = currentItem?.mediaMetadata?.albumTitle ?: ""

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val contentPendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val prevIntent = Intent(this, PlaybackService::class.java).apply { action = ACTION_PREV }
        val prevPendingIntent = PendingIntent.getService(this, 1, prevIntent, PendingIntent.FLAG_IMMUTABLE)

        val playPauseIntent = Intent(this, PlaybackService::class.java).apply {
            action = if (p.isPlaying) ACTION_PAUSE else ACTION_PLAY
        }
        val playPausePendingIntent = PendingIntent.getService(this, 2, playPauseIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val nextIntent = Intent(this, PlaybackService::class.java).apply { action = ACTION_NEXT }
        val nextPendingIntent = PendingIntent.getService(this, 3, nextIntent, PendingIntent.FLAG_IMMUTABLE)

        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setSubText(if (album.isNotEmpty()) album else null)
            .setContentIntent(contentPendingIntent)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(p.isPlaying)
            .addAction(android.R.drawable.ic_media_previous, "Previous", prevPendingIntent)
            .addAction(
                if (p.isPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (p.isPlaying) "Pause" else "Play",
                playPausePendingIntent
            )
            .addAction(android.R.drawable.ic_media_next, "Next", nextPendingIntent)
            .setStyle(
                MediaStyleNotificationHelper.MediaStyle(session)
                    .setShowActionsInCompactView(0, 1, 2)
            )

        // largeIcon: square artwork with gradient (compact notification + Android < 12 expanded)
        currentArtworkBitmap?.let {
            notificationBuilder.setLargeIcon(processArtworkForNotification(it))
        }

        // Expanded notification: full waveform composite via RemoteViews
        // On Android 12+ MediaStyle overrides this for media sessions, but it still
        // shows correctly on Android 11 and below.
        val composite = currentCompositeBitmap
        if (composite != null) {
            try {
                val expandedView = RemoteViews(packageName, R.layout.notification_waveform)
                expandedView.setImageViewBitmap(R.id.notif_composite, composite)
                notificationBuilder.setCustomBigContentView(expandedView)
            } catch (_: Exception) {}
        }

        try {
            startForeground(NOTIFICATION_ID, notificationBuilder.build())
        } catch (_: Exception) {}
    }

    // ── Waveform composite renderer ────────────────────────────────────────────
    //
    // Renders the mirrored-bar waveform (as in the reference image) over a
    // darkened album-art background, then adds track title + artist text.
    // The result is used as:
    //   • MediaMetadata artwork  → Android 12+ lock-screen media player
    //   • Notification largeIcon → compact notification row
    //   • RemoteViews bigContentView → expanded notification (pre-12 Android)

    private var currentCompositeBitmap: Bitmap? = null

    /**
     * Generates the mirrored waveform bar bitmap at the requested size.
     * Bars are seeded from [seed] so they are consistent per track.
     */
    private fun generateWaveformBitmap(width: Int, height: Int, seed: Long): Bitmap {
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        val barCount = 54
        val totalSlot = width.toFloat() / barCount
        val barW = totalSlot * 0.62f
        val centerY = height / 2f
        val maxHalf = height * 0.44f
        val minHalf = height * 0.06f
        val radius = barW / 2f

        val barPaint = Paint().apply {
            isAntiAlias = true
            style = Paint.Style.FILL
        }

        val rng = java.util.Random(seed)

        for (i in 0 until barCount) {
            // Gaussian bell envelope: tallest bars in the centre
            val norm = (i - barCount / 2.0) / (barCount / 2.8)
            val envelope = Math.exp(-(norm * norm)).toFloat().coerceIn(0f, 1f)

            val raw = rng.nextFloat() * 0.55f + 0.45f
            val half = (raw * maxHalf * envelope).coerceAtLeast(minHalf)

            val x = i * totalSlot + (totalSlot - barW) / 2f

            // Gradient: bright teal core → lighter tip
            val topY = centerY - half
            val botY = centerY + half
            barPaint.shader = LinearGradient(
                x, topY, x, botY,
                intArrayOf(
                    Color.argb(220, 100, 200, 240),
                    Color.argb(255, 79,  195, 247), // #4FC3F7 — Material Blue 300
                    Color.argb(255, 79,  195, 247),
                    Color.argb(220, 100, 200, 240)
                ),
                floatArrayOf(0f, 0.3f, 0.7f, 1f),
                Shader.TileMode.CLAMP
            )

            // Top half bar
            canvas.drawRoundRect(RectF(x, topY, x + barW, centerY), radius, radius, barPaint)
            // Bottom half bar (mirror)
            canvas.drawRoundRect(RectF(x, centerY, x + barW, botY), radius, radius, barPaint)
        }

        // Centre line
        val linePaint = Paint().apply {
            color = Color.argb(80, 255, 255, 255)
            strokeWidth = 1.5f
            isAntiAlias = true
        }
        canvas.drawLine(0f, centerY, width.toFloat(), centerY, linePaint)

        return bmp
    }

    /**
     * Builds the full composite bitmap:
     *   Album art (blurred by dark overlay) → waveform bars → title/artist text → progress bar.
     */
    fun buildWaveformCompositeBitmap(
        artwork: Bitmap?,
        title: CharSequence?,
        artist: CharSequence?,
        positionFraction: Float = 0f,
    ): Bitmap {
        val W = 800
        val H = 280
        val bmp = Bitmap.createBitmap(W, H, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)

        // ── 1. Album art background ──────────────────────────────────────────
        if (artwork != null) {
            val scaled = Bitmap.createScaledBitmap(artwork, W, H, true)
            canvas.drawBitmap(scaled, 0f, 0f, null)
        } else {
            canvas.drawColor(Color.parseColor("#FF050510"))
        }

        // Dark gradient overlay (heavier at top + bottom for text legibility)
        val palette = if (artwork != null)
            androidx.palette.graphics.Palette.from(artwork).generate() else null
        val darkColor = palette?.getDarkMutedColor(Color.parseColor("#CC050510"))
            ?: Color.parseColor("#CC050510")

        val overlayPaint = Paint()
        overlayPaint.shader = LinearGradient(
            0f, 0f, 0f, H.toFloat(),
            intArrayOf(
                Color.argb(200, Color.red(darkColor), Color.green(darkColor), Color.blue(darkColor)),
                Color.argb(110, 0, 0, 0),
                Color.argb(180, 0, 0, 0)
            ),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, 0f, W.toFloat(), H.toFloat(), overlayPaint)

        // ── 2. Waveform bars ─────────────────────────────────────────────────
        val waveW = W - 48
        val waveH = (H * 0.50f).toInt()
        val waveTop = (H * 0.06f)
        val seed = artwork?.hashCode()?.toLong() ?: 0L
        val waveBmp = generateWaveformBitmap(waveW, waveH, seed)
        canvas.drawBitmap(waveBmp, 24f, waveTop, null)

        // ── 3. Progress bar ───────────────────────────────────────────────────
        val progY = H * 0.63f
        val trackPaint = Paint().apply {
            color = Color.argb(80, 255, 255, 255)
            strokeWidth = 3f
            strokeCap = Paint.Cap.ROUND
            isAntiAlias = true
        }
        val fillPaint = Paint().apply {
            color = Color.argb(220, 79, 195, 247) // #4FC3F7
            strokeWidth = 3f
            strokeCap = Paint.Cap.ROUND
            isAntiAlias = true
        }
        val thumbPaint = Paint().apply {
            color = Color.WHITE
            isAntiAlias = true
        }
        val progLeft = 24f
        val progRight = W - 24f
        canvas.drawLine(progLeft, progY, progRight, progY, trackPaint)
        val thumbX = progLeft + (progRight - progLeft) * positionFraction.coerceIn(0f, 1f)
        canvas.drawLine(progLeft, progY, thumbX, progY, fillPaint)
        canvas.drawCircle(thumbX, progY, 6f, thumbPaint)

        // ── 4. Track text ────────────────────────────────────────────────────
        val titlePaint = Paint().apply {
            color = Color.WHITE
            textSize = 30f
            isAntiAlias = true
            typeface = Typeface.DEFAULT_BOLD
        }
        val artistPaint = Paint().apply {
            color = Color.argb(200, 255, 255, 255)
            textSize = 22f
            isAntiAlias = true
        }
        val textX = 24f
        canvas.drawText(
            (title?.toString() ?: "Unknown").take(38),
            textX, H * 0.79f, titlePaint
        )
        canvas.drawText(
            (artist?.toString() ?: "").take(44),
            textX, H * 0.92f, artistPaint
        )

        return bmp
    }

    private fun processArtworkForNotification(artwork: Bitmap): Bitmap {
        // Kept for largeIcon (square crop). Composite is used for expanded view + lock screen.
        val size = 256
        val scaled = Bitmap.createScaledBitmap(artwork, size, size, true)
        val mutable = scaled.copy(Bitmap.Config.ARGB_8888, true)
        val canvas = Canvas(mutable)
        val palette = androidx.palette.graphics.Palette.from(artwork).generate()
        val dark = palette.getDarkMutedColor(palette.getMutedColor(0xFF1A1A2E.toInt()))
        val gp = Paint()
        gp.shader = LinearGradient(0f, size * 0.5f, 0f, size.toFloat(),
            intArrayOf(Color.TRANSPARENT, dark), null, Shader.TileMode.CLAMP)
        canvas.drawRect(0f, size * 0.5f, size.toFloat(), size.toFloat(), gp)
        return mutable
    }

    private fun emitPlaybackState() {
        val p = player ?: return
        val stateMap = mapOf(
            "isPlaying" to p.isPlaying,
            "positionMs" to p.currentPosition,
            "durationMs" to (p.duration.takeIf { it != C.TIME_UNSET } ?: 0L),
            "playbackState" to p.playbackState
        )
        methodChannel?.invokeMethod("onPlaybackStateChanged", stateMap)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        instance = null
        equalizer?.release(); equalizer = null
        bassBoost?.release(); bassBoost = null
        virtualizer?.release(); virtualizer = null
        loudnessEnhancer?.release(); loudnessEnhancer = null
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        super.onDestroy()
    }
}
