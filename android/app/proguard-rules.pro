# Promemoria pianificati: flutter_local_notifications serializza con Gson,
# che ha bisogno dei tipi generici anche dopo R8.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
