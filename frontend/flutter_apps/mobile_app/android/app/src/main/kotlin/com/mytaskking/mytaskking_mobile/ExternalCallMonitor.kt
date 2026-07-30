package com.mytaskking.mytaskking_mobile

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.telephony.PhoneStateListener
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

/**
 * Detects cellular / telecom-framework calls while a MyTaskKing VoIP session is
 * live. Emits:
 *   ringing  — another call is presenting
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
    /** True after we saw an incoming cellular/telecom ring during this session. */
    private var sawExternalRing = false
    private var lastCallState = TelephonyManager.CALL_STATE_IDLE
    private var baselineAudioMode = AudioManager.MODE_NORMAL
    private var telephonyRegistered = false

    private var telephonyManager: TelephonyManager? = null
    private var phoneStateListener: PhoneStateListener? = null
    private var telephonyCallback: TelephonyCallback? = null
    private var audioManager: AudioManager? = null

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun start(context: Context) {
        if (monitoring) {
            // Permission may have been granted after the first start — re-register telephony.
            if (!telephonyRegistered && hasPhoneStatePermission(context)) {
                registerTelephony(context)
            }
            return
        }
        monitoring = true
        appContext = context.applicationContext
        lastTelecomInCall = readTelecomInCall(context)
        externalRinging = false
        sawExternalRing = false
        lastCallState = readCallState(context)
        audioManager = context.getSystemService(AudioManager::class.java)
        baselineAudioMode = audioManager?.mode ?: AudioManager.MODE_NORMAL
        registerTelephony(context)
        startPolling()
    }

    fun stop() {
        monitoring = false
        externalRinging = false
        sawExternalRing = false
        stopPolling()
        unregisterTelephony()
        appContext = null
        lastTelecomInCall = false
        lastCallState = TelephonyManager.CALL_STATE_IDLE
        audioManager = null
        baselineAudioMode = AudioManager.MODE_NORMAL
    }

    /** Flutter lifecycle hint — user left MyTaskKing UI while another call was ringing. */
    fun notifyAppBackgrounded() {
        if (!monitoring) return
        val ctx = appContext ?: return
        if (externalRinging || sawExternalRing) {
            emitAccepted("app_background")
            return
        }
        // Fallback when RINGING was missed but the dialer took over the screen.
        if (readCallState(ctx) == TelephonyManager.CALL_STATE_RINGING) {
            emitAccepted("app_background_ringing")
        }
    }

    private fun hasPhoneStatePermission(context: Context): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.READ_PHONE_STATE,
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun startPolling() {
        stopPolling()
        val runnable = object : Runnable {
            override fun run() {
                if (!monitoring) return
                val ctx = appContext ?: return
                pollTelecom(ctx)
                pollCallState(ctx)
                pollAudioMode()
                mainHandler.postDelayed(this, 900L)
            }
        }
        pollRunnable = runnable
        mainHandler.post(runnable)
    }

    private fun stopPolling() {
        pollRunnable?.let { mainHandler.removeCallbacks(it) }
        pollRunnable = null
    }

    private fun pollTelecom(context: Context) {
        val inCall = readTelecomInCall(context)
        if (inCall && !lastTelecomInCall) {
            markExternalRing("telecom_in_call")
        } else if (!inCall && !externalRinging) {
            sawExternalRing = false
        }
        lastTelecomInCall = inCall
    }

    private fun pollCallState(context: Context) {
        val state = readCallState(context)
        when {
            state == TelephonyManager.CALL_STATE_RINGING &&
                lastCallState != TelephonyManager.CALL_STATE_RINGING -> {
                markExternalRing("poll_ringing")
            }
            sawExternalRing &&
                state == TelephonyManager.CALL_STATE_OFFHOOK &&
                lastCallState == TelephonyManager.CALL_STATE_RINGING -> {
                emitAccepted("cellular_offhook_poll")
            }
        }
        lastCallState = state
    }

    private fun pollAudioMode() {
        if (!sawExternalRing) return
        val mode = audioManager?.mode ?: return
        // VoIP uses IN_COMMUNICATION; a answered cellular call often switches to IN_CALL.
        if (mode == AudioManager.MODE_IN_CALL &&
            baselineAudioMode != AudioManager.MODE_IN_CALL
        ) {
            emitAccepted("audio_mode_in_call")
        }
    }

    @Suppress("MissingPermission")
    private fun readTelecomInCall(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        if (!hasPhoneStatePermission(context)) return false
        return try {
            val telecom = context.getSystemService(TelecomManager::class.java)
            telecom?.isInCall == true
        } catch (_: SecurityException) {
            false
        } catch (_: Exception) {
            false
        }
    }

    @Suppress("MissingPermission", "DEPRECATION")
    private fun readCallState(context: Context): Int {
        if (!hasPhoneStatePermission(context)) {
            return TelephonyManager.CALL_STATE_IDLE
        }
        return try {
            val tm = context.getSystemService(TelephonyManager::class.java)
                ?: return TelephonyManager.CALL_STATE_IDLE
            tm.callState
        } catch (_: SecurityException) {
            TelephonyManager.CALL_STATE_IDLE
        } catch (_: Exception) {
            TelephonyManager.CALL_STATE_IDLE
        }
    }

    private fun registerTelephony(context: Context) {
        unregisterTelephony()
        if (!hasPhoneStatePermission(context)) {
            telephonyRegistered = false
            return
        }
        val tm = context.getSystemService(TelephonyManager::class.java) ?: return
        telephonyManager = tm
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
                override fun onCallStateChanged(state: Int) {
                    handleCallStateChanged(state)
                }
            }
            telephonyCallback = callback
            try {
                tm.registerTelephonyCallback(context.mainExecutor, callback)
                telephonyRegistered = true
            } catch (_: SecurityException) {
                telephonyCallback = null
                telephonyRegistered = false
            }
            return
        }
        @Suppress("DEPRECATION")
        val listener = object : PhoneStateListener() {
            @Deprecated("Deprecated in Java")
            override fun onCallStateChanged(state: Int, phoneNumber: String?) {
                handleCallStateChanged(state)
            }
        }
        phoneStateListener = listener
        try {
            @Suppress("DEPRECATION")
            tm.listen(listener, PhoneStateListener.LISTEN_CALL_STATE)
            telephonyRegistered = true
        } catch (_: SecurityException) {
            phoneStateListener = null
            telephonyRegistered = false
        }
    }

    private fun handleCallStateChanged(state: Int) {
        when (state) {
            TelephonyManager.CALL_STATE_RINGING -> markExternalRing("cellular_ringing")
            TelephonyManager.CALL_STATE_OFFHOOK -> {
                if (sawExternalRing || lastCallState == TelephonyManager.CALL_STATE_RINGING) {
                    emitAccepted("cellular_offhook")
                }
            }
            TelephonyManager.CALL_STATE_IDLE -> {
                if (!externalRinging) {
                    sawExternalRing = false
                }
            }
        }
        lastCallState = state
    }

    private fun markExternalRing(source: String) {
        if (!monitoring) return
        externalRinging = true
        sawExternalRing = true
        emit("ringing")
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
        telephonyRegistered = false
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
        sawExternalRing = false
        mainHandler.post {
            eventSink?.success(mapOf("type" to "accepted", "reason" to reason))
        }
    }
}
