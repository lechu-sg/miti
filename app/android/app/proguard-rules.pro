# Reglas del ofuscador (R8) para la compilación de release.
#
# Por qué existe este archivo: el SDK de AdMob arrastra WorkManager, que usa Room.
# Room crea su base buscando por reflexión una clase generada (WorkDatabase_Impl).
# R8 no la ve referenciada, la renombra y la app se cae al arrancar con
# "Failed to create an instance of androidx.work.impl.WorkDatabase".

# Room y sus implementaciones generadas.
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.** { *; }
-keep @androidx.room.Entity class * { *; }
-dontwarn androidx.room.paging.**

# WorkManager: su inicializador corre antes que la app.
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class androidx.startup.** { *; }
-dontwarn androidx.work.**

# Anuncios de Google.
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Firebase: hoy no hay credenciales, pero la app igual carga las clases.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
