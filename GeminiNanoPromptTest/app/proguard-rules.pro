# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Keep ML Kit GenAI classes
-keep class com.google.mlkit.genai.** { *; }

# Keep data model classes for Gson
-keep class com.example.geminanotestapp.model.** { *; }
-keepclassmembers class com.example.geminanotestapp.model.** { *; }
