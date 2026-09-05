import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ⚠️ غيّر هذا لاسم الحزمة الفعلي لتطبيقك قبل النشر على المتاجر
    namespace = "com.example.inventory_analyzer"

    // ثابت يدويًا (وليس flutter.compileSdkVersion) — هذا بالضبط ما وثّقه
    // القسم 3 من دليل الأعطال: القيمة الافتراضية المضمّنة في Flutter قد تكون
    // أقل مما تحتاجه بعض الحزم. سكربت tool/patch_compile_sdk.py يعالج نفس
    // المشكلة داخل الحزم الخارجية في pub-cache؛ هذا السطر يعالجها في وحدة
    // التطبيق نفسها من الأساس.
    // ✅ مُصحَّح فعليًا بناءً على خطأ CI حقيقي بتاريخ 2026-09-03: رُفع من 36
    // إلى 37 لأن receive_sharing_intent (المُضافة لدعم Share/Open With — قسم
    // 3-7) تتطلب compileSdk 37+ فعليًا — فشلت :app:checkReleaseAarMetadata
    // بهذا بالضبط عند 36 (راجع رسالة الخطأ الكاملة في نص الطلب وقتها).
    // حدّث MIN_COMPILE_SDK في tool/patch_compile_sdk.py بالتوازي مع أي رفع
    // مستقبلي لهذا الرقم.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.inventory_analyzer"
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
                // ⚠️ درس رقم 6 في دليل الأعطال: منذ Java 9+ نوع الكيستور
                // الافتراضي PKCS12، ويجب أن تكون storePassword وkeyPassword
                // متطابقتين تمامًا وإلا فشل التوقيع لاحقًا بخطأ
                // BadPaddingException غامض لا علاقة له ظاهريًا بكلمات المرور.
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // يسمح بنجاح بناء تجريبي بلا كيستور، لكنه غير صالح للنشر
                signingConfigs.getByName("debug")
            }
            // ⚠️ مُعطَّل عمدًا في هذا الإصدار الأول: isMinifyEnabled/isShrinkResources
            // يقلّلان حجم APK لكنهما يضيفان احتمال فشل غير متوقع (تعارض قواعد
            // ProGuard/R8 مع إحدى الحزم) لا يمكن اختباره هنا بلا Flutter SDK.
            // فعّلهما لاحقًا بعد تأكيد نجاح بناء أساسي نظيف أولًا، لا قبله.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // ✅ مُصحَّح فعليًا بناءً على خطأ CI حقيقي بتاريخ 2026-08-30: مهمة
    // lintVitalAnalyzeRelease (تُشغَّل تلقائيًا مع أي بناء release) تنهار
    // بعلّة داخلية موثَّقة صراحة من الأداة نفسها ("this is a bug in lint or
    // one of the libraries it depends on") عند تحليل ExifDataCopier.java من
    // حزمة image_picker_android — لا علاقة لها بصحة كود هذا المشروع.
    // checkReleaseBuilds تحديدًا (وليس lintOptions القديمة) هي الخاصية
    // الرسمية الحالية لتعطيل فحوصات lint "الحرجة" المرتبطة تلقائيًا بأي بناء
    // release، دون التأثير على عمل التطبيق إطلاقًا.
    lint {
        checkReleaseBuilds = false
        // اقتراح الأداة نفسها في رسالة الخطأ (المُفحِّص المنهار CommentDetector
        // يُستخدَم من هذين الفحصين تحديدًا) — إضافي احتياطي بلا أي ضرر
        disable.addAll(setOf("EasterEgg", "StopShip"))
    }
}

flutter {
    source = "../.."
}

// ✅ مُصحَّح فعليًا بناءً على خطأ CI حقيقي بتاريخ 2026-08-29: كتلة
// android { kotlinOptions { jvmTarget = ... } } القديمة صارت خطأ ترجمة
// صريحًا (وليس مجرد تحذير) مع AGP 9 — راجع رسالة الخطأ:
//   'var jvmTarget: String' is deprecated. Please migrate to the
//   compilerOptions DSL.
// البديل الحديث الموثَّق رسميًا (docs.flutter.dev/release/breaking-changes/
// migrate-to-built-in-kotlin/for-app-developers) هو كتلة kotlin{} منفصلة
// خارج android{} تمامًا، كما هنا:
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}
