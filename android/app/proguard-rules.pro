# yt-dlp bridge + jackson models are accessed through reflection.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.** { *; }
-keep class com.videograb.app.** { *; }
-dontwarn com.yausername.**
