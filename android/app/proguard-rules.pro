# Keep MediaPipe classes
-keep class com.google.mediapipe.** { *; }
-keepclassmembers class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep MediaPipe proto classes
-keep class com.google.mediapipe.proto.** { *; }
-keepclassmembers class com.google.mediapipe.proto.** { *; }

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-keepclassmembers class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# Keep Google AI Edge classes
-keep class com.google.ai.edge.** { *; }
-keepclassmembers class com.google.ai.edge.** { *; }
-dontwarn com.google.ai.edge.**
