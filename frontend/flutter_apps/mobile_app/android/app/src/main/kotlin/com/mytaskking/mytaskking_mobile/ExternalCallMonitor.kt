package com.mytaskking.mytaskking_mobile

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import io.flutter.plugin.common.EventChannel

/**
 * Detects cellular / telecom-framework calls (WhatsApp, Phone, etc.) while a
 * MyTaskKing VoIP session is live. Emits:
 *   ringing  — another call is presenting (user should stay on MyTaskKing or hang up)
 *   accepted — user took the other call; Flutter should end the MyTaskKing session
 */
object ExternalCallMonitor {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var monitoring = false
    private var eventSink: EventChannel.EventSink? = null
    private var appContext: Context? = null

    private var pollRunnable: Runnable? = null
    private var lastTelecomInCall = false
    private var externalRinging = false

    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: TelephonyCallback? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun start(context: Context) {
        if (monitoring) return
        monitoring = true
        appContext = context.applicationContext
        lastTelecomInCall = readTelecomInCall(context)
        externalRinging = false
        registerTelephony(context)
        startPolling()
    }

    fun stop() {
        monitoring = false
        externalRinging = false
        stopPolling()
        unregisterTelephony()
        appContext = null
        lastTelecomInCall = false
    }

    /** Flutter lifecycle hint — user left MyTaskKing UI while another call was ringing. */
    fun notifyAppBackgrounded() {
        if (!monitoring || !externalRinging) return
        emitAccepted("app_background")
    }

    private fun startPolling() {
        stopPolling()
        val runnable = object : Runnable {
            override fun run() {
                if (!monitoring) return
                val ctx = appContext ?: return
                val inCall = readTelecomInCall(ctx)
                if (inCall && !lastTelecomInCall) {
                    externalRinging = true
                    emit("ringing")
                } else if (!inCall) {
                    externalRinging = false
                }
                lastTelecomInCall = inCall
                mainHandler.postDelayed(this, 1200L)
            }
        }
        pollRunnable = runnable
        mainHandler.post(runnable)
    }

    private fun stopPolling() {
        pollRunnable?.let { mainHandler.removeCallbacks(it) }
        pollRunnable = null
    }

    @Suppress("MissingPermission")
    private fun readTelecomInCall(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return try {
            val telecom = context.getSystemService(TelecomManager::class.java)
            telecom?.isInCall == true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    private fun registerTelephony(context: Context) {
        val tm = context.getSystemService(TelephonyManager::class.java) ?: return
        telephonyManager = tm
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    when (state) {
                        TelephonyManager.CALL_STATE_RINGING -> {
                            externalRinging = true
                            emit("ringing")
                        }
                        TelephonyManager.CALL_STATE_OFFHOOK -> emitAccepted("cellular_offhook")
                    }
                }
            }
            telephonyCallback = callback
            try {
                tm.registerTelephonyCallback(context.mainExecutor, callback)
            } catch (_: SecurityException) {
                telephonyCallback = null
            }
            return
        }
        @Suppress("DEPRECATION")
        val listener = object : PhoneStateListener() {
            @Deprecated("Deprecated in Java")
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                when (state) {
                    TelephonyManager.CALL_STATE_RINGING -> {
                        externalRinging = true
                        emit("ringing")
                    }
                    TelephonyManager.CALL_STATE_OFFHOOK -> emitAccepted("cellular_offhook")
                }
            }
        }
        phoneStateListener = listener
        try {
            @Suppress("DEPRECATION")
            tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
        } catch (_: SecurityException) {
            phoneStateListener = null
        }
    }

    private fun unregisterTelephony() {
        val tm = telephonyManager
        if (tm != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                telephonyCallback?.let {
                    try {
                        tm.unregisterTelephonyCallback(it)
                    } catch (_: Exception) {}
                }
            } else {
                @Suppress("DEPRECATION")
                phoneStateListener?.let {
                    try {
                        tm.listen(it, PhoneStateListener.LISTEN_NONE)
                    } catch (_: Exception) {}
                }
            }
        }
        telephonyCallback = null
        phoneStateListener = null
        telephonyManager = null
    }

    private fun emit(type: String) {
        if (!monitoring) return
        mainHandler.post {
            eventSink?.success(mapOf("type" to type))
        }
    }

    private fun emitAccepted(reason: String) {
        if (!monitoring) return
        externalRinging = false
        mainHandler.post {
            eventSink?.success(mapOf("type" to "accepted", "reason" to reason))
        }
    }
}
