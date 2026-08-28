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
    // ⚠️ إصداري AGP وKotlin أدناه معقولان وحاليان وقت كتابة هذا المشروع، لكن
    // لم تُختبر هذه القيم فعليًا (لا Flutter SDK متاحًا في بيئة الإنشاء) —
    // إن رفضهما Gradle في أول تشغيل CI، ارفعهما لآخر إصدار مستقر مذكور في
    // https://docs.flutter.dev/release/breaking-changes/android-java-gradle-agp-kgp-compatibility
    id("com.android.application") version "9.3.0" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
