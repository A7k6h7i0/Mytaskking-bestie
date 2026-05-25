package com.mytaskking.mytaskking_mobile

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val launchChannel = "mytaskking/launch_intent"
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
}
