# مكتبات POS اختيارية (Switch Pos / Gertec / Clover / Newland …)
-dontwarn br.com.execucao.posmp_api.**
-dontwarn br.com.gertec.gedi.**
-dontwarn br.com.tectoy.**
-dontwarn br.com.tectoylib.**
-dontwarn com.clover.sdk.**
-dontwarn com.newland.**
-dontwarn com.perto.pos.**
-dontwarn com.wizarpos.**

# Flutter / Firebase
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
