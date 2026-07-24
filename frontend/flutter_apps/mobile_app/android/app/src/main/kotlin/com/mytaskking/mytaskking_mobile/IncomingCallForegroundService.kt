package com.mytaskking.mytaskking_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/**
 * Owns incoming-call ringing while Flutter is backgrounded or killed.
 *
 * A normal notification sound is controlled by the OS and often stops after
 * roughly ten seconds. This foreground service loops the device ringtone until
 * the user accepts/declines or the backend's no-answer window expires.
 */
class IncomingCallForegroundService : Service() {
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private var ringtonePlayer: MediaPlayer? = null
    private var systemRingtone: Ringtone? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var notificationId: Int = DEFAULT_NOTIFICATION_ID
    private var ringingSoundUrl: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        createChannel()
        notificationId = intent?.getIntExtra(EXTRA_NOTIFICATION_ID, DEFAULT_NOTIFICATION_ID)
            ?: DEFAULT_NOTIFICATION_ID
        ringingSoundUrl = intent?.getStringExtra(EXTRA_RINGING_SOUND_URL)?.trim()?.takeIf { it.isNotEmpty() }
        active = true
        activeKey = intent?.getStringExtra("callId")
            ?: intent?.getStringExtra("meetingSlug")
        acquireWakeLock()
        startForeground(notificationId, buildNotification(intent))
        startRinging()
        timeoutHandler.removeCallbacksAndMessages(null)
        timeoutHandler.postDelayed({ stopSelf() }, RING_TIMEOUT_MS)
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        active = false
        activeKey = null
        timeoutHandler.removeCallbacksAndMessages(null)
        stopRinging()
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        getSystemService(NotificationManager::class.java).cancel(notificationId)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun startRinging() {
        stopRinging()
        val customUrl = ringingSoundUrl
        if (!customUrl.isNullOrEmpty()) {
            try {
                startMediaPlayerLoop(Uri.parse(customUrl))
                return
            } catch (_: Exception) {
                // Fall back to the device default ringtone below.
            }
        }
        val audioManager = getSystemService(AudioManager::class.java)
        try {
            @Suppress("DEPRECATION")
            audioManager.mode = AudioManager.MODE_RINGTONE
            requestAudioFocus(audioManager)

            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val ringtone = RingtoneManager.getRingtone(this, ringtoneUri)
            if (ringtone != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    ringtone.audioAttributes = AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ringtone.isLooping = true
                }
                ringtone.play()
                systemRingtone = ringtone
                // API < 28 cannot loop Ringtone — fall back to MediaPlayer for continuous ring.
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                    startMediaPlayerLoop(ringtoneUri)
                }
                return
            }
            startMediaPlayerLoop(ringtoneUri)
        } catch (_: Exception) {
            try {
                startMediaPlayerLoop(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                )
            } catch (_: Exception) {
                stopRinging()
            }
        }
    }

    private fun startMediaPlayerLoop(uri: Uri?) {
        if (uri == null) return
        stopMediaPlayer()
        ringtonePlayer = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            setDataSource(this@IncomingCallForegroundService, uri)
            isLooping = true
            setOnPreparedListener { player -> player.start() }
            setOnErrorListener { _, _, _ ->
                stopMediaPlayer()
                false
            }
            prepareAsync()
        }
    }

    private fun stopMediaPlayer() {
        try {
            ringtonePlayer?.stop()
        } catch (_: Exception) {
        }
        try {
            ringtonePlayer?.release()
        } catch (_: Exception) {
        }
        ringtonePlayer = null
    }

    private fun requestAudioFocus(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attrs)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener { /* keep ringing through brief ducking */ }
                .build()
            audioManager.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                null,
                AudioManager.STREAM_RING,
                AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
            )
        }
    }

    private fun abandonAudioFocus(audioManager: AudioManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }

    private fun stopRinging() {
        try {
            systemRingtone?.stop()
        } catch (_: Exception) {
        }
        systemRingtone = null
        stopMediaPlayer()
        try {
            val audioManager = getSystemService(AudioManager::class.java)
            @Suppress("DEPRECATION")
            audioManager.mode = AudioManager.MODE_NORMAL
            abandonAudioFocus(audioManager)
        } catch (_: Exception) {
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val power = getSystemService(PowerManager::class.java)
            wakeLock = power.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "mytaskking:incoming_call_ringing"
            ).apply {
                setReferenceCounted(false)
                acquire(RING_TIMEOUT_MS + 5_000L)
            }
        } catch (_: Exception) {
            wakeLock = null
        }
    }

    private fun buildNotification(source: Intent?): Notification {
        val type = source?.getStringExtra(EXTRA_TYPE) ?: "call.incoming"
        val fromName = source?.getStringExtra(EXTRA_FROM_NAME) ?: "Someone"
        val title = source?.getStringExtra(EXTRA_TITLE)
            ?: if (type == "meeting.invited") "Meeting invite" else "Incoming call"
        val body = source?.getStringExtra(EXTRA_BODY)
            ?: if (type == "meeting.invited") "$fromName invited you to a meeting"
            else "$fromName is calling"

        val displayIntent = targetIntent(source, accepted = false)
        val acceptIntent = targetIntent(source, accepted = true)
        val displayPendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            displayIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val acceptPendingIntent = PendingIntent.getActivity(
            this,
            notificationId + 1,
            acceptIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val declinePendingIntent = PendingIntent.getBroadcast(
            this,
            notificationId + 2,
            Intent(this, NotificationActionReceiver::class.java).apply {
                action = NotificationActionReceiver.ACTION_CALL_DECLINE
                putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(NotificationActionReceiver.EXTRA_API_BASE_URL, source?.getStringExtra(EXTRA_API_BASE_URL))
                putExtra(NotificationActionReceiver.EXTRA_ACTION_TOKEN, source?.getStringExtra(EXTRA_ACTION_TOKEN))
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(NotificationIcon.smallIcon(this))
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSound(null)
            .setVibrate(longArrayOf(0, 700, 500, 700))
            .setWhen(System.currentTimeMillis())
            .setUsesChronometer(true)
            .setShowWhen(true)
            .setContentIntent(displayPendingIntent)
            .setFullScreenIntent(displayPendingIntent, true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(
                Notification.CallStyle.forIncomingCall(
                    Person.Builder().setName(fromName).build(),
                    declinePendingIntent,
                    acceptPendingIntent
                )
            )
        } else {
            builder
                .addAction(applicationInfo.icon, "Decline", declinePendingIntent)
                .addAction(applicationInfo.icon, "Accept", acceptPendingIntent)
        }
        return builder.build()
    }

    private fun targetIntent(source: Intent?, accepted: Boolean): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            source?.extras?.keySet()?.forEach { key ->
                when (val value = source.extras?.get(key)) {
                    is String -> putExtra(key, value)
                    is Int -> putExtra(key, value)
                    is Long -> putExtra(key, value)
                    is Boolean -> putExtra(key, value)
                }
            }
            putExtra("acceptCall", accepted)
            putExtra("nativeRinging", true)
            putExtra("notificationId", notificationId)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Incoming calls",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Continuous incoming MyTaskKing call ringing"
            setSound(null, null)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 700, 500, 700)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_STOP = "com.mytaskking.mytaskking_mobile.STOP_INCOMING_CALL"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_TYPE = "type"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_FROM_NAME = "fromName"
        const val EXTRA_RINGING_SOUND_URL = "ringingSoundUrl"
        const val EXTRA_API_BASE_URL = "apiBaseUrl"
        const val EXTRA_ACTION_TOKEN = "actionToken"
        private const val CHANNEL_ID = "incoming_calls_loop_v1"
        private const val DEFAULT_NOTIFICATION_ID = 4702
        private const val RING_TIMEOUT_MS = 60_000L

        @Volatile
        var active: Boolean = false
            private set
        @Volatile
        var activeKey: String? = null
            private set

        fun start(context: Context, data: Map<String, String>, type: String) {
            val key = data["callId"] ?: data["meetingSlug"] ?: data["body"] ?: type
            val intent = Intent(context, IncomingCallForegroundService::class.java).apply {
                putExtra(EXTRA_NOTIFICATION_ID, BestieFirebaseMessagingService.notificationIdFor(key))
                putExtra(EXTRA_TYPE, type)
                data.forEach { (name, value) -> putExtra(name, value) }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context, key: String? = null) {
            if (key != null && activeKey != null && key != activeKey) return
            context.stopService(Intent(context, IncomingCallForegroundService::class.java))
        }
    }
}
