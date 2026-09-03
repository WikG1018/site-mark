import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val requireReleaseSigning = providers.gradleProperty("requireReleaseSigning")
    .orNull
    .equals("true", ignoreCase = true)
if (requireReleaseSigning && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Release signing is required, but android/key.properties is missing",
    )
}
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

android {
    namespace = "io.github.wikg1018.sitemark"
    // Android 17 SDK (platforms;android-37.0). targetSdk 37 opts into the
    // Android 17 targeted behavior changes. Large-screen orientation,
    // background activity launch, and background audio remain no-ops for
    // this system-camera, orientation-unlocked app. Local network access
    // is no longer a no-op: D-023 NAS sync to a LAN box needs
    // ACCESS_LOCAL_NETWORK (see the main manifest).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (and other Android plugins) require JDK
        // 11+ APIs (e.g. java.time) that are unavailable on the Android runtime
        // without desugaring. Enable core-library desugaring so debug/release
        // APK builds succeed on minSdk 31+.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "io.github.wikg1018.sitemark"
        minSdk = 31
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Disable R8 code minification and resource shrinking. R8 obfuscation
            // breaks flutter_rust_bridge FFI bindings and WorkManager callback
            // dispatchers, causing the app to crash immediately on launch in
            // release builds. SiteMark is an offline app, so APK size is not a
            // critical concern.
            isMinifyEnabled = false
            isShrinkResources = false
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
