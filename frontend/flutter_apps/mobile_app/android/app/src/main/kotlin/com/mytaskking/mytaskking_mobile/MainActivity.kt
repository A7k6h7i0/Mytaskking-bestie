package com.mytaskking.mytaskking_mobile

import android.app.NotificationManager
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val launchChannel = "mytaskking/launch_intent"
    private val callNotificationChannel = "mytaskking/call_notification"
    private val proximityMethodChannel = "mytaskking/proximity"
    private val proximityEventChannel = "mytaskking/proximity_events"
    private var latestLaunchPayload: Map<String, String?>? = null

    private var sensorManager: SensorManager? = null
    private var proximitySensor: Sensor? = null
    private var proximityWakeLock: PowerManager.WakeLock? = null
    private var proximityListener: SensorEventListener? = null
    private var proximitySink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        BestieFirebaseMessagingService.createCallNotificationChannel(this)
        BestieFirebaseMessagingService.createMessageNotificationChannel(this)
        latestLaunchPayload = payloadFrom(intent)
        cancelNotificationFromIntent(intent)
        applyCallWindowFlags(latestLaunchPayload)
    }

    private var launchMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannel)
        launchMethodChannel?.setMethodCallHandler { call, result ->
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
                        CallForegroundService.stop(this)
                        result.success(null)
                    }
                    "cancelIncoming" -> {
                        @Suppress("UNCHECKED_CAST")
                        cancelIncomingNotification(call.arguments as? Map<String, Any?>)
                        result.success(null)
                    }
                    "startIncoming" -> {
                        @Suppress("UNCHECKED_CAST")
                        startIncomingNotification(call.arguments as? Map<String, Any?>)
                        result.success(null)
                    }
                    "isIncomingActive" -> result.success(IncomingCallForegroundService.active)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, proximityMethodChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        enableProximity()
                        result.success(null)
                    }
                    "disable" -> {
                        disableProximity()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, proximityEventChannel)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    proximitySink = events
                }

                override fun onCancel(arguments: Any?) {
                    proximitySink = null
                }
            })
    }

    override fun onDestroy() {
        disableProximity()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        latestLaunchPayload = payloadFrom(intent)
        cancelNotificationFromIntent(intent)
        applyCallWindowFlags(latestLaunchPayload)
        notifyLaunchPayload(latestLaunchPayload)
    }

    private fun notifyLaunchPayload(payload: Map<String, String?>?) {
        if (payload == null) return
        launchMethodChannel?.invokeMethod("onLaunchPayload", payload)
    }

    @Suppress("DEPRECATION")
    private fun enableProximity() {
        disableProximity()
        val power = getSystemService(POWER_SERVICE) as PowerManager
        try {
            proximityWakeLock = power.newWakeLock(
                PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
                "mytaskking:proximity"
            ).apply {
                acquire(60 * 60 * 1000L)
            }
        } catch (_: Exception) {
            proximityWakeLock = null
        }

        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        proximitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        if (proximitySensor == null) return

        proximityListener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val near = event.values[0] < event.sensor.maximumRange
                runOnUiThread { proximitySink?.success(near) }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
        }
        sensorManager?.registerListener(
            proximityListener,
            proximitySensor,
            SensorManager.SENSOR_DELAY_NORMAL
        )
    }

    private fun disableProximity() {
        proximityListener?.let { listener ->
            sensorManager?.unregisterListener(listener)
        }
        proximityListener = null
        proximitySensor = null
        sensorManager = null
        if (proximityWakeLock?.isHeld == true) {
            proximityWakeLock?.release()
        }
        proximityWakeLock = null
    }

    private fun payloadFrom(intent: Intent?): Map<String, String?>? {
        if (intent == null) return null
        val type = intent.getStringExtra("type")
        val hasCallTarget = type == "call.incoming" ||
            type == "call.active" ||
            type == "meeting.invited"
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
            "acceptCall" to intent.getBooleanExtra("acceptCall", false).toString(),
            "nativeRinging" to intent.getBooleanExtra("nativeRinging", false).toString(),
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
        val isIncoming = intent.getStringExtra("type") == "call.incoming" ||
            intent.getStringExtra("type") == "meeting.invited"
        if (isIncoming && !intent.getBooleanExtra("acceptCall", false)) return
        val id = intent.getIntExtra("notificationId", -1)
        if (id != -1) getSystemService(NotificationManager::class.java).cancel(id)
        if (isIncoming) IncomingCallForegroundService.stop(this)
    }

    private fun cancelIncomingNotification(args: Map<String, Any?>?) {
        val key = args?.get("callId")?.toString()?.takeIf { it.isNotBlank() }
            ?: args?.get("meetingSlug")?.toString()?.takeIf { it.isNotBlank() }
            ?: return
        IncomingCallForegroundService.stop(this, key)
        getSystemService(NotificationManager::class.java).cancel(
            BestieFirebaseMessagingService.notificationIdFor(key)
        )
    }

    private fun startIncomingNotification(args: Map<String, Any?>?) {
        if (args == null) return
        val type = args["type"]?.toString() ?: "call.incoming"
        val data = mutableMapOf<String, String>()
        for ((key, value) in args) {
            val text = value?.toString()?.trim().orEmpty()
            if (text.isNotEmpty()) data[key.toString()] = text
        }
        if (data.isEmpty()) return
        IncomingCallForegroundService.start(this, data, type)
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
