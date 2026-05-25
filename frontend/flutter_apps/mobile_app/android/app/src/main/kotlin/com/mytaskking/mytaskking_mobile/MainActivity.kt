package com.mytaskking.mytaskking_mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val launchChannel = "mytaskking/launch_intent"
    private val callNotificationChannel = "mytaskking/call_notification"
    private var latestLaunchPayload: Map<String, String?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        BestieFirebaseMessagingService.createCallNotificationChannel(this)
        latestLaunchPayload = payloadFrom(intent)
        applyCallWindowFlags(latestLaunchPayload)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInitialPayload") {
                    result.success(latestLaunchPayload)
                    latestLaunchPayload = null
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, callNotificationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "show" -> {
                        @Suppress("UNCHECKED_CAST")
                        showOngoingCallNotification(call.arguments as? Map<String, Any?>)
                        result.success(null)
                    }
                    "hide" -> {
                        getSystemService(NotificationManager::class.java).cancel(4701)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        latestLaunchPayload = payloadFrom(intent)
        applyCallWindowFlags(latestLaunchPayload)
    }

    private fun payloadFrom(intent: Intent?): Map<String, String?>? {
        val type = intent?.getStringExtra("type") ?: return null
        if (type != "call.incoming" && type != "meeting.invited") return null
        return mapOf(
            "type" to type,
            "callId" to intent.getStringExtra("callId"),
            "meetingSlug" to intent.getStringExtra("meetingSlug"),
            "mode" to intent.getStringExtra("mode"),
            "fromName" to intent.getStringExtra("fromName")
        )
    }

    private fun applyCallWindowFlags(payload: Map<String, String?>?) {
        if (payload == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun showOngoingCallNotification(args: Map<String, Any?>?) {
        val title = args?.get("title")?.toString() ?: "Call in progress"
        val body = args?.get("body")?.toString() ?: "Tap to return"
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("type", if (args?.get("meetingSlug") != null) "meeting.invited" else "call.incoming")
            putExtra("callId", args?.get("callId")?.toString())
            putExtra("meetingSlug", args?.get("meetingSlug")?.toString())
            putExtra("mode", args?.get("mode")?.toString())
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            4701,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "active_calls",
                "Active calls",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, "active_calls")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(pendingIntent)
            .build()
        getSystemService(NotificationManager::class.java).notify(4701, notification)
    }
}
