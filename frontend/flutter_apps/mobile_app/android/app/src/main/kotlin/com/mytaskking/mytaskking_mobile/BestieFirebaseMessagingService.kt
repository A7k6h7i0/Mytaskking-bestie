package com.mytaskking.mytaskking_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class BestieFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val type = data["type"] ?: return
        if (type != "call.incoming" && type != "meeting.invited") return

        createCallNotificationChannel(this)

        val title = data["title"]
            ?: if (type == "meeting.invited") "Meeting invite" else "Incoming call"
        val body = data["body"]
            ?: data["fromName"]?.let { "$it is calling" }
            ?: "Tap to join"

        val previewIntent = Intent(this, IncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("type", type)
            putExtra("callId", data["callId"])
            putExtra("meetingSlug", data["meetingSlug"])
            putExtra("mode", data["mode"])
            putExtra("fromName", data["fromName"])
        }
        val requestCode = (data["callId"] ?: data["meetingSlug"] ?: System.currentTimeMillis().toString()).hashCode()
        val pendingIntent = PendingIntent.getActivity(
            this,
            requestCode,
            previewIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CALLS_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(false)
            .setAutoCancel(true)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            .setVibrate(longArrayOf(0, 700, 500, 700))
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .build()

        getSystemService(NotificationManager::class.java)
            .notify(requestCode, notification)
        wakeBriefly()
        try {
            startActivity(previewIntent)
        } catch (_: Exception) {
            // Android may block background activity starts on some devices.
            // The full-screen notification above remains the reliable path.
        }
    }

    private fun wakeBriefly() {
        try {
            val power = getSystemService(PowerManager::class.java)
            @Suppress("DEPRECATION")
            val wakeLock = power.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "mytaskking:incoming_call"
            )
            wakeLock.acquire(5_000)
        } catch (_: Exception) {
        }
    }

    companion object {
        const val CALLS_CHANNEL_ID = "calls"

        fun createCallNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                CALLS_CHANNEL_ID,
                "Calls and meeting invites",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming MyTaskKing calls and meeting invites"
                enableVibration(true)
                setSound(ringtoneUri, attrs)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
