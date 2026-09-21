# Flutter Wrapper Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# ONNX Runtime Keep Rules (Crucial for JNI reflection from native C++)
-keep class ai.onnxruntime.** { *; }
-keep interface ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** {
    <fields>;
    <methods>;
}
-dontwarn ai.onnxruntime.**

# Meta Wearable DAT SDK Keep Rules
-keep class com.meta.wearable.** { *; }
-keep interface com.meta.wearable.** { *; }
-keepclassmembers class com.meta.wearable.** {
    <fields>;
    <methods>;
}
-dontwarn com.meta.wearable.**

# Silero VAD / Audio / Camera plugins
-keep class com.github.char5742.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-keep class io.flutter.plugins.camera.** { *; }
-keep class com.ryanheise.audiosession.** { *; }

# General JNI and Native Methods Keep Rules
-keepclasseswithmembernames class * {
    native <methods>;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
