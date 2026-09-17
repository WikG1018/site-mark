# Keep rules for R8 release minification.
#
# Flutter embedding ships its own consumer rules; these cover the plugins
# whose entry points are reached only via reflection / JNI.

# WorkManager: the Dart top-level dispatcher and plugin callback classes.
-keep class androidx.work.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_local_notifications: scheduled receivers and plugin registrant.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# flutter_rust_bridge: native library name and generated bindings surface.
-keep class io.github.wikg1018.sitemark.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Play Core / Flutter deferred components are unused; silence missing-class
# warnings that otherwise fail the build when shrinkResources is on.
-dontwarn com.google.android.play.core.**
