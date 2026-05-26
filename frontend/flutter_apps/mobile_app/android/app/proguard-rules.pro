# MyTaskKing release-mode ProGuard / R8 rules.
#
# We rely on `proguard-android-optimize.txt` for the baseline plus the
# Flutter-managed default rules. Everything below is just our own SDK keep
# list — packages that use reflection or JNI and would otherwise get
# stripped or renamed and crash at runtime.

# ----- Flutter & Dart -----
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.embedding.** { *; }

# ----- Agora RTC -----
-keep class io.agora.**       { *; }
-keep class com.agora.rtc.**  { *; }
-dontwarn io.agora.**

# ----- Firebase / FCM -----
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# ----- audioplayers + record -----
-keep class xyz.luan.audioplayers.** { *; }
-keep class com.llfbandit.record.** { *; }
-dontwarn xyz.luan.audioplayers.**
-dontwarn com.llfbandit.record.**

# ----- permission_handler -----
-keep class com.baseflow.** { *; }

# ----- General Kotlin coroutines reflection-free safety -----
-dontwarn kotlinx.coroutines.debug.**
-dontwarn kotlinx.coroutines.flow.**

# ----- Keep classes with native methods -----
-keepclasseswithmembernames class * {
    native <methods>;
}
