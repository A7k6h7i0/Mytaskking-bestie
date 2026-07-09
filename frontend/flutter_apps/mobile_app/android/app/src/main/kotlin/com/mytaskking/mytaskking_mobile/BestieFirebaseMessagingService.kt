package com.mytaskking.mytaskking_mobile

import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
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
        if (data.isEmpty()) return

        val type = data["type"]
        val kind = data["kind"]
        val clientApp = data["clientApp"]?.trim()?.lowercase()
        if (!clientApp.isNullOrBlank() &&
            clientApp != "mytaskking" &&
            clientApp != "web"
        ) {
            return
        }
        if (type == "call.ended") {
            val callId = data["callId"]
            IncomingCallForegroundService.stop(this, callId)
            CallForegroundService.stop(this, callId)
            if (!callId.isNullOrBlank()) {
                getSystemService(NotificationManager::class.java)
                    .cancel(notificationIdFor(callId))
            }
            return
        }
        if (type == "call.incoming" || type == "meeting.invited") {
            // Start native ringing when the app is backgrounded/killed OR when the
            // screen is off — Flutter ringtone plugins cannot play in those states.
            if (isAppInForeground() && isInteractiveScreen()) return
            try {
                IncomingCallForegroundService.start(this, data, type)
            } catch (_: Exception) {
                // Some OEMs may reject a background foreground-service start.
                // Fall back to the normal high-priority call notification.
                showIncomingCallNotification(data, type)
            }
            wakeBriefly()
            return
        }

        if (type == "emergency.alert") {
            if (isAppInForeground()) return
            showEmergencyNotification(data)
            wakeBriefly()
            return
        }

        if ((type == "chat.message" || kind == "CHAT" || kind == "MENTION") &&
            !data["channelId"].isNullOrBlank()
        ) {
            if (isAppInForeground()) return
            showMessageNotification(data)
        }
    }

    private fun showEmergencyNotification(data: Map<String, String>) {
        createEmergencyNotificationChannel(this)
        val fromName = data["fromName"] ?: "Admin"
        val escalation = data["escalation"] == "1"
        val title = if (escalation) "🚨 URGENT: response required" else "🚨 Emergency alert"
        val body = data["message"]?.takeIf { it.isNotBlank() } ?: "$fromName needs your immediate attention"
        val notificationId = notificationIdFor(data["alertId"] ?: body)
        val openIntent = targetIntent(data, "emergency.alert", notificationId)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = notificationBuilder(EMERGENCY_CHANNEL_ID)
            .setSmallIcon(NotificationIcon.smallIcon(this))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM))
            .setVibrate(longArrayOf(0, 800, 400, 800, 400, 800))
            .setContentIntent(openPendingIntent)
            .setFullScreenIntent(openPendingIntent, true)
        getSystemService(NotificationManager::class.java)
            .notify(notificationId, builder.build())
    }

    private fun showIncomingCallNotification(data: Map<String, String>, type: String) {
        createCallNotificationChannel(this)

        val fromName = data["fromName"] ?: "Someone"
        val title = data["title"]
            ?: if (type == "meeting.invited") "Meeting invite" else "Incoming call"
        val body = data["body"]
            ?: if (type == "meeting.invited") "$fromName invited you to a meeting" else "$fromName is calling"
        val notificationId = notificationIdFor(data["callId"] ?: data["meetingSlug"] ?: body)

        val openIntent = targetIntent(data, type, notificationId)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val acceptPendingIntent = PendingIntent.getActivity(
            this,
            notificationId + 1,
            targetIntent(data, type, notificationId).apply {
                putExtra("acceptCall", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val declinePendingIntent = PendingIntent.getBroadcast(
            this,
            notificationId + 17,
            Intent(this, NotificationActionReceiver::class.java).apply {
                action = NotificationActionReceiver.ACTION_CALL_DECLINE
                putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(NotificationActionReceiver.EXTRA_API_BASE_URL, data["apiBaseUrl"])
                putExtra(NotificationActionReceiver.EXTRA_ACTION_TOKEN, data["actionToken"])
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = notificationBuilder(CALLS_CHANNEL_ID)
            .setSmallIcon(NotificationIcon.smallIcon(this))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_CALL)
            .setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
            .setVibrate(longArrayOf(0, 700, 500, 700))
            .setWhen(System.currentTimeMillis())
            .setUsesChronometer(true)
            .setShowWhen(true)
            .setContentIntent(openPendingIntent)
            // Ring full-screen like a real phone call even when the device is
            // locked / screen-off (needs USE_FULL_SCREEN_INTENT, declared in
            // the manifest, + CATEGORY_CALL above for Android 14 eligibility).
            .setFullScreenIntent(openPendingIntent, true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val person = Person.Builder().setName(fromName).build()
            builder.setStyle(
                Notification.CallStyle.forIncomingCall(
                    person,
                    declinePendingIntent,
                    acceptPendingIntent
                )
            )
        } else {
            builder
                .addAction(applicationInfo.icon, "Decline", declinePendingIntent)
                .addAction(applicationInfo.icon, "Accept", acceptPendingIntent)
        }

        getSystemService(NotificationManager::class.java)
            .notify(notificationId, builder.build())
    }

    private fun showMessageNotification(data: Map<String, String>) {
        createMessageNotificationChannel(this)

        val title = data["title"] ?: "New message"
        val body = data["body"] ?: "Tap to open"
        val notificationId = notificationIdFor(data["notificationId"] ?: data["messageId"] ?: body)
        val openIntent = targetIntent(data, data["type"] ?: "chat.message", notificationId)
        val openPendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = notificationBuilder(MESSAGES_CHANNEL_ID)
            .setSmallIcon(NotificationIcon.smallIcon(this))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setPriority(Notification.PRIORITY_HIGH)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setAutoCancel(true)
            .setContentIntent(openPendingIntent)

        val actionToken = data["actionToken"]
        val apiBaseUrl = data["apiBaseUrl"]
        if (!actionToken.isNullOrBlank() && !apiBaseUrl.isNullOrBlank()) {
            val replyIntent = Intent(this, NotificationActionReceiver::class.java).apply {
                action = NotificationActionReceiver.ACTION_CHAT_REPLY
                putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(NotificationActionReceiver.EXTRA_API_BASE_URL, apiBaseUrl)
                putExtra(NotificationActionReceiver.EXTRA_ACTION_TOKEN, actionToken)
            }
            val replyPendingIntent = PendingIntent.getBroadcast(
                this,
                notificationId + 31,
                replyIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or mutablePendingIntentFlag()
            )
            val remoteInput = RemoteInput.Builder(NotificationActionReceiver.KEY_REPLY_TEXT)
                .setLabel("Reply")
                .build()
            val replyAction = Notification.Action.Builder(
                applicationInfo.icon,
                "Reply",
                replyPendingIntent
            ).addRemoteInput(remoteInput)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                replyAction.setAllowGeneratedReplies(true)
            }
            builder.addAction(replyAction.build())
        }

        getSystemService(NotificationManager::class.java)
            .notify(notificationId, builder.build())
    }

    private fun targetIntent(
        data: Map<String, String>,
        type: String,
        notificationId: Int
    ): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            data.forEach { (key, value) ->
                if (key != "notificationId") putExtra(key, value)
            }
            putExtra("type", type)
            putExtra("notificationId", notificationId)
        }
    }

    private fun notificationBuilder(channelId: String): Notification.Builder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
    }

    private fun mutablePendingIntentFlag(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
    }

    private fun isAppInForeground(): Boolean {
        return try {
            val manager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val currentPackageName = applicationContext.packageName
            manager.runningAppProcesses?.any { process ->
                process.processName == currentPackageName &&
                    (process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                        process.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE)
            } == true
        } catch (_: Exception) {
            false
        }
    }

    private fun isInteractiveScreen(): Boolean {
        return try {
            getSystemService(PowerManager::class.java).isInteractive
        } catch (_: Exception) {
            true
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
        private const val MESSAGES_CHANNEL_ID = "messages"
        private const val EMERGENCY_CHANNEL_ID = "emergency"

        fun notificationIdFor(value: String): Int {
            return value.hashCode().let { if (it == Int.MIN_VALUE) 1 else kotlin.math.abs(it) }
        }

        fun createEmergencyNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                EMERGENCY_CHANNEL_ID,
                "Emergency alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Urgent admin emergency sirens"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
                setSound(alarmUri, attrs)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

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

        fun createMessageNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            // Explicit notification sound so chat messages audibly ring/chime
            // (don't rely on per-OEM channel defaults).
            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val channel = NotificationChannel(
                MESSAGES_CHANNEL_ID,
                "Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Chat messages and mentions"
                enableVibration(true)
                setSound(soundUri, attrs)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }
}
