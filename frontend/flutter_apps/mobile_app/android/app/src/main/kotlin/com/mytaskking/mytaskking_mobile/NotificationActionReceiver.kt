package com.mytaskking.mytaskking_mobile

import android.app.NotificationManager
import android.app.RemoteInput
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        if (notificationId != -1) {
            context.getSystemService(NotificationManager::class.java)?.cancel(notificationId)
        }

        val apiBaseUrl = intent.getStringExtra(EXTRA_API_BASE_URL)?.trimEnd('/')
        val token = intent.getStringExtra(EXTRA_ACTION_TOKEN)
        if (apiBaseUrl.isNullOrBlank() || token.isNullOrBlank()) return

        val pending = goAsync()
        Thread {
            try {
                when (action) {
                    ACTION_CALL_DECLINE -> postJson(
                        "$apiBaseUrl/notifications/actions/call-decline",
                        JSONObject().put("token", token)
                    )
                    ACTION_CHAT_REPLY -> {
                        val reply = RemoteInput.getResultsFromIntent(intent)
                            ?.getCharSequence(KEY_REPLY_TEXT)
                            ?.toString()
                            ?.trim()
                        if (!reply.isNullOrBlank()) {
                            postJson(
                                "$apiBaseUrl/notifications/actions/chat-reply",
                                JSONObject()
                                    .put("token", token)
                                    .put("body", reply)
                            )
                        }
                    }
                }
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }.start()
    }

    private fun postJson(url: String, body: JSONObject) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 15_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        try {
            conn.outputStream.use { out ->
                out.write(body.toString().toByteArray(Charsets.UTF_8))
            }
            val stream = if (conn.responseCode >= 400) conn.errorStream else conn.inputStream
            stream?.close()
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        const val ACTION_CALL_DECLINE = "com.mytaskking.mytaskking_mobile.ACTION_CALL_DECLINE"
        const val ACTION_CHAT_REPLY = "com.mytaskking.mytaskking_mobile.ACTION_CHAT_REPLY"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_API_BASE_URL = "apiBaseUrl"
        const val EXTRA_ACTION_TOKEN = "actionToken"
        const val KEY_REPLY_TEXT = "replyText"
    }
}
