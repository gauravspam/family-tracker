# Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Dio
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep our models (serialization)
-keep class com.familytracker.admin_app.** { *; }

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
}

# Strip unused code
-optimizationpasses 5
-allowaccessmodification
-repackageclasses ''
