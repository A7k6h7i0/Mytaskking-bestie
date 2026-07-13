import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Load the release signing config from android/key.properties (gitignored).
// Falls back to debug signing when the file is absent (e.g. CI without secrets).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.mytaskking.mytaskking_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.mytaskking.mytaskking_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // ABI targeting is handled by Flutter CLI flags (--target-platform /
        // --split-per-abi). Do not set ndk.abiFilters here — it conflicts with
        // --split-per-abi. Non-arm64 libs are still stripped via agora_size.gradle.kts.
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the upload keystore from key.properties when present; otherwise
            // fall back to debug so `flutter run --release` still works locally.
            signingConfig = if (keystorePropertiesFile.exists())
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
            // R8 shrinks Java/Kotlin + unused resources. ProGuard keep rules below
            // protect Agora, Firebase, and Flutter plugin entry points.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
    // R8 full-mode does aggressive class merging + tree shaking. Safe for
    // release because we keep the SDK packages explicitly below.
    packaging {
        jniLibs {
            @Suppress("UNCHECKED_CAST")
            val agoraExcludes =
                rootProject.extra["agoraExtensionExcludePaths"] as Set<String>
            @Suppress("UNCHECKED_CAST")
            val abiExcludes =
                rootProject.extra["nonArm64AbiExcludePaths"] as Set<String>
            excludes += agoraExcludes
            excludes += abiExcludes
        }
        resources {
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/INDEX.LIST",
            )
        }
    }
}

// Relative path only — absolute paths with spaces (e.g. "ADD PHONE BOOK") break
// Flutter's Gradle compile step on Windows (`/main.dart` not found).
flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.firebase:firebase-messaging:24.1.2")
    implementation("androidx.documentfile:documentfile:1.1.0")
    implementation("androidx.activity:activity-ktx:1.9.3")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
