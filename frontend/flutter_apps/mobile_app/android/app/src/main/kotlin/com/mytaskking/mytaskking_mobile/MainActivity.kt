package com.mytaskking.mytaskking_mobile

import android.app.NotificationManager
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
        BestieFirebaseMessagingService.createMessageNotificationChannel(this)
        latestLaunchPayload = payloadFrom(intent)
        cancelNotificationFromIntent(intent)
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
                        startCallForegroundService(call.arguments as? Map<String, Any?>)
                        result.success(null)
                    }
                    "hide" -> {
                        stopService(Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_STOP
                        })
                        getSystemService(NotificationManager::class.java)
                            .cancel(CallForegroundService.NOTIFICATION_ID)
                        result.success(null)
                    }
                    "cancelIncoming" -> {
                        @Suppress("UNCHECKED_CAST")
                        cancelIncomingNotification(call.arguments as? Map<String, Any?>)
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
        cancelNotificationFromIntent(intent)
        applyCallWindowFlags(latestLaunchPayload)
    }

    private fun payloadFrom(intent: Intent?): Map<String, String?>? {
        if (intent == null) return null
        val type = intent.getStringExtra("type")
        val hasCallTarget = type == "call.incoming" || type == "meeting.invited"
        val hasChatTarget = !intent.getStringExtra("channelId").isNullOrBlank()
        val hasTaskTarget = !intent.getStringExtra("taskId").isNullOrBlank()
        if (!hasCallTarget && !hasChatTarget && !hasTaskTarget) return null
        return mapOf(
            "type" to (type ?: if (hasChatTarget) "chat.message" else null),
            "callId" to intent.getStringExtra("callId"),
            "meetingSlug" to intent.getStringExtra("meetingSlug"),
            "mode" to intent.getStringExtra("mode"),
            "fromName" to intent.getStringExtra("fromName"),
            "channelId" to intent.getStringExtra("channelId"),
            "messageId" to intent.getStringExtra("messageId"),
            "taskId" to intent.getStringExtra("taskId"),
            "kind" to intent.getStringExtra("kind"),
            "notificationId" to if (intent.hasExtra("notificationId")) {
                intent.getIntExtra("notificationId", -1).toString()
            } else {
                null
            }
        )
    }

    private fun applyCallWindowFlags(payload: Map<String, String?>?) {
        if (payload == null) return
        val type = payload["type"]
        if (type != "call.incoming" && type != "meeting.invited") return
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

    private fun cancelNotificationFromIntent(intent: Intent?) {
        if (intent == null || !intent.hasExtra("notificationId")) return
        val id = intent.getIntExtra("notificationId", -1)
        if (id != -1) getSystemService(NotificationManager::class.java).cancel(id)
    }

    private fun cancelIncomingNotification(args: Map<String, Any?>?) {
        val key = args?.get("callId")?.toString()?.takeIf { it.isNotBlank() }
            ?: args?.get("meetingSlug")?.toString()?.takeIf { it.isNotBlank() }
            ?: return
        getSystemService(NotificationManager::class.java).cancel(
            BestieFirebaseMessagingService.notificationIdFor(key)
        )
    }

    private fun startCallForegroundService(args: Map<String, Any?>?) {
        val serviceIntent = Intent(this, CallForegroundService::class.java).apply {
            putExtra(CallForegroundService.EXTRA_TITLE, args?.get("title")?.toString())
            putExtra(CallForegroundService.EXTRA_BODY, args?.get("body")?.toString())
            putExtra(CallForegroundService.EXTRA_CALL_ID, args?.get("callId")?.toString())
            putExtra(
                CallForegroundService.EXTRA_MEETING_SLUG,
                args?.get("meetingSlug")?.toString()
            )
            putExtra(CallForegroundService.EXTRA_MODE, args?.get("mode")?.toString())
            putExtra(
                CallForegroundService.EXTRA_STARTED_AT,
                (args?.get("startedAtMs") as? Number)?.toLong()
                    ?: System.currentTimeMillis()
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

}
