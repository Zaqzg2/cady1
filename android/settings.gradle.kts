pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // ✅ مُصحَّح فعليًا بناءً على خطأ CI حقيقي بتاريخ 2026-08-28:
    //   "Your project's Kotlin version (2.2.10) is lower than Flutter's
    //    minimum supported version of 2.2.20"
    // 2.1.0 (القيمة السابقة) كانت أقل من الحد الأدنى الذي يفرضه
    // dev.flutter.flutter-gradle-plugin نفسه وقت البناء، وليس مجرد توصية.
    // 2.3.20 هنا تعطي هامش أمان فوق 2.2.20 مباشرة (وليس مطابقة الحد الأدنى
    // تمامًا) تحسبًا لأي رفع لاحق بسيط لهذا الحد الأدنى مع تحديثات Flutter.
    // إن ظهر هذا التحذير مرة أخرى مستقبلًا برقم أعلى، ارفع الرقم هنا لأي
    // إصدار Kotlin مستقر ≥ الرقم المذكور في رسالة الخطأ نفسها.
    id("com.android.application") version "9.3.0" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
