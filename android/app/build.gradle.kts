import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release 签名
//
// 文件布局（CI 在 .github/workflows/release.yml 里生成，密钥只来自仓库 Secrets）：
//   android/key.properties   storePassword / keyPassword / keyAlias / storeFile(相对 android/)
//   android/keystore.jks
//
// 两个文件都不存在时（本地开发、或没配 Secrets 的 CI 构建）→ 回退 debug 签名，
// release 构建依然能成功，只是不能覆盖安装签名不同的正式版。
// ---------------------------------------------------------------------------
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keyPropertiesFile.exists()
val keyProperties = Properties().apply {
    if (hasReleaseKeystore) {
        keyPropertiesFile.inputStream().use { load(it) }
    }
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
        // versionCode / versionName 来自 pubspec.yaml（0.4.14 / 4140）。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 有 key.properties 用正式签名；没有就用 debug 签名（保证构建可跑通）。
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
