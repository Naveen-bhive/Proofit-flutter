# Flutter engine / embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Play Core (deferred components) - flutter embedding references these
# even when split-install isn't used; suppress missing-class warnings.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Firebase / Google Play Services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Google Sign-In
-keep class com.google.android.gms.auth.** { *; }

# Google Maps
-keep class com.google.maps.android.** { *; }

# Razorpay (payments) - keep SDK + reflection-based callback methods
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/removal/parameter
-keepattributes JavascriptInterface
-keepattributes *Annotation*

# okhttp (used by razorpay / socket_io_client / dio's underlying stack)
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# socket_io_client / engine.io
-keep class io.socket.** { *; }
-dontwarn io.socket.**
-keep class org.json.** { *; }

# flutter_local_notifications (scheduled/foreground-service notification
# components are referenced via manifest + reflection, not direct calls)
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# RevenueCat (purchases_flutter)
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# Keep Parcelable CREATORs and Serializable classes (common source of
# obscure crashes after obfuscation if missed)
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep native method names (JNI)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Enum values()/valueOf() used via reflection by some plugins
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
