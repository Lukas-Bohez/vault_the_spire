# Keep Flutter entry points
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Suppress optional deferred-components Play Core task API references.
# This app does not use deferred components directly.
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
