plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Skip Android Lint for release builds: pure overhead here and AGP 9 lint
    // crashes in this offline/mirror setup. Kotlin/Dart analysis is done separately.
    lint {
        checkReleaseBuilds = false
        abortOnError = false
        checkDependencies = false
    }
    namespace = "app.keepsake.keepsake"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 与原 APK 对齐：applicationId = app.keepsake.chat（inventory.md §1 [确定]）。
        // namespace 保持 flutter create 生成的 app.keepsake.keepsake（R 类/清单里 .MainActivity
        // 仍按 namespace 解析），两者可以不同，互不影响。
        applicationId = "app.keepsake.chat"
        // 原 APK：minSdk 24 / targetSdk 36（inventory.md §1）。
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // versionCode / versionName 来自 pubspec.yaml（0.4.2 / 4031，与原 APK 一致）。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
