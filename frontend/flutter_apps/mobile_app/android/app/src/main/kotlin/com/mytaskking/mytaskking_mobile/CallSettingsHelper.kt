package com.mytaskking.mytaskking_mobile

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings

object CallSettingsHelper {
    /** Opens the closest OEM call / recording settings screen, or general Settings. */
    fun openCallRecordingSettings(context: Context): Boolean {
        val candidates = listOf(
            // Samsung
            component("com.samsung.android.dialer", "com.samsung.android.dialer.settings.CallSettingsActivity"),
            component("com.samsung.android.dialer", "com.samsung.android.dialer.settings.DialerSettingsActivity"),
            component("com.samsung.android.incallui", "com.samsung.android.incallui.callsettings.CallSettingsActivity"),
            // Xiaomi / Redmi / POCO
            component("com.android.phone", "com.android.phone.settings.CallRecordSetting"),
            component("com.android.contacts", "com.android.contacts.activities.ContactSettingsActivity"),
            // Oppo / Realme / ColorOS
            component("com.coloros.phonemanager", "com.coloros.phonemanager.module.callrecord.CallRecordSetting"),
            component("com.oplus.dialer", "com.oplus.dialer.settings.DialerSettingsActivity"),
            // Vivo
            component("com.android.dialer", "com.android.dialer.app.settings.DialerSettingsActivity"),
            // OnePlus
            component("com.oneplus.dialer", "com.oneplus.dialer.settings.DialerSettingsActivity"),
            // Google Phone (general dialer settings — recording may not exist)
            component("com.google.android.dialer", "com.google.android.dialer.extensions.GoogleDialtactsActivity"),
            // Generic telephony
            Intent(Settings.ACTION_WIRELESS_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )

        for (intent in candidates) {
            if (tryStart(context, intent)) return true
        }
        return false
    }

    private fun component(pkg: String, cls: String): Intent =
        Intent().setComponent(ComponentName(pkg, cls))

    private fun tryStart(context: Context, intent: Intent): Boolean {
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pm = context.packageManager
        val resolved = pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        if (resolved == null) return false
        return try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }
}
