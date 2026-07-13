package com.mytaskking.mytaskking_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder

class TelecallerRecordingForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        createChannel()
        activeCallId = intent?.getStringExtra(EXTRA_CALL_ID)
        startForeground(NOTIFICATION_ID, buildNotification(intent))
        return START_STICKY
    }

    override fun onDestroy() {
        activeCallId = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(source: Intent?): Notification {
        val title = source?.getStringExtra(EXTRA_TITLE) ?: "Recording telecaller call"
        val body = source?.getStringExtra(EXTRA_BODY)
            ?: "Use speakerphone for clearer capture. Return to MyTaskKing when done."

        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
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
            .setSmallIcon(NotificationIcon.smallIcon(this))
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Telecaller recording",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps microphone recording active during phone calls"
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        const val ACTION_STOP = "com.mytaskking.mytaskking_mobile.STOP_TELECALLER_RECORDING"
        const val EXTRA_CALL_ID = "callId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val NOTIFICATION_ID = 4702
        private const val CHANNEL_ID = "telecaller_recording"

        @Volatile
        var activeCallId: String? = null
            private set

        fun start(context: Context, callId: String?) {
            val serviceIntent = Intent(context, TelecallerRecordingForegroundService::class.java).apply {
                putExtra(EXTRA_CALL_ID, callId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TelecallerRecordingForegroundService::class.java).apply {
                action = ACTION_STOP
            })
            context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
            activeCallId = null
        }
    }
}
