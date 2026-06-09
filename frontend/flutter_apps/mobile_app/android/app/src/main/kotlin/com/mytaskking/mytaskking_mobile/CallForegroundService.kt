package com.mytaskking.mytaskking_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.net.wifi.WifiManager

class CallForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        createChannel()
        acquireWakeLock()
        acquireWifiLock()
        startForeground(NOTIFICATION_ID, buildNotification(intent))
        return START_STICKY
    }

    override fun onDestroy() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        if (wifiLock?.isHeld == true) wifiLock?.release()
        wifiLock = null
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun acquireWifiLock() {
        if (wifiLock?.isHeld == true) return
        try {
            val wifi = applicationContext.getSystemService(WifiManager::class.java)
            wifiLock = wifi.createWifiLock(
                WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                "mytaskking:active_call_wifi"
            ).apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (_: Exception) {
            wifiLock = null
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(PowerManager::class.java)
        wakeLock = power.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "mytaskking:active_call"
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun buildNotification(source: Intent?): Notification {
        val title = source?.getStringExtra(EXTRA_TITLE) ?: "Call in progress"
        val body = source?.getStringExtra(EXTRA_BODY) ?: "Tap to return"
        val startedAt = source?.getLongExtra(EXTRA_STARTED_AT, 0L)
            ?.takeIf { it > 0L } ?: System.currentTimeMillis()
        val callId = source?.getStringExtra(EXTRA_CALL_ID)
        val meetingSlug = source?.getStringExtra(EXTRA_MEETING_SLUG)
        val mode = source?.getStringExtra(EXTRA_MODE) ?: "voice"

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("type", if (meetingSlug != null) "meeting.invited" else "call.incoming")
            putExtra("callId", callId)
            putExtra("meetingSlug", meetingSlug)
            putExtra("mode", mode)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            NOTIFICATION_ID,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setWhen(startedAt)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Active calls",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps active MyTaskKing calls connected"
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_STOP = "com.mytaskking.mytaskking_mobile.STOP_ACTIVE_CALL"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_CALL_ID = "callId"
        const val EXTRA_MEETING_SLUG = "meetingSlug"
        const val EXTRA_MODE = "mode"
        const val EXTRA_STARTED_AT = "startedAtMs"
        const val NOTIFICATION_ID = 4701
        private const val CHANNEL_ID = "active_calls"
    }
}
