package com.mytaskking.mytaskking_mobile

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class IncomingCallActivity : Activity() {
    private var ringtone: Ringtone? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showOverLockScreen()
        startRinging()
        setContentView(buildContent())
    }

    override fun onDestroy() {
        stopRinging()
        super.onDestroy()
    }

    private fun showOverLockScreen() {
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
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    private fun startRinging() {
        try {
            ringtone = RingtoneManager.getRingtone(
                this,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone?.isLooping = true
            }
            ringtone?.play()
        } catch (_: Exception) {
        }
    }

    private fun stopRinging() {
        try {
            ringtone?.stop()
        } catch (_: Exception) {
        }
    }

    private fun buildContent(): LinearLayout {
        val type = intent.getStringExtra("type") ?: "call.incoming"
        val from = intent.getStringExtra("fromName") ?: "Someone"
        val isMeeting = type == "meeting.invited"
        val titleText = if (isMeeting) "Meeting invite" else "Incoming call"
        val bodyText = if (isMeeting) "$from invited you to a meeting" else "$from is calling"

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(48, 48, 48, 48)
            setBackgroundColor(Color.rgb(11, 18, 32))
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )

            addView(TextView(context).apply {
                text = titleText
                setTextColor(Color.WHITE)
                textSize = 30f
                gravity = Gravity.CENTER
            })
            addView(TextView(context).apply {
                text = bodyText
                setTextColor(Color.rgb(203, 213, 225))
                textSize = 18f
                gravity = Gravity.CENTER
                setPadding(0, 18, 0, 56)
            })
            addView(Button(context).apply {
                text = "Accept"
                textSize = 18f
                setOnClickListener {
                    stopRinging()
                    startActivity(mainIntent())
                    finish()
                }
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply { setMargins(0, 0, 0, 18) })
            addView(Button(context).apply {
                text = "Decline"
                textSize = 18f
                setOnClickListener {
                    stopRinging()
                    finish()
                }
            }, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ))
        }
    }

    private fun mainIntent(): Intent {
        return Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("type", intent.getStringExtra("type"))
            putExtra("callId", intent.getStringExtra("callId"))
            putExtra("meetingSlug", intent.getStringExtra("meetingSlug"))
            putExtra("mode", intent.getStringExtra("mode"))
            putExtra("fromName", intent.getStringExtra("fromName"))
        }
    }
}
