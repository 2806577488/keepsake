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
        // versionCode / versionName 来自 pubspec.yaml。
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 单 ABI 打包（E-01 / N-1）。
        //
        // 为什么必须过滤：Flutter 只把引擎（libflutter/libapp/libsqlite3）放进
        // 目标 ABI 目录，但插件的 .so（libdartjni、libdatastore_shared_counter）
        // 会被 AGP 打进所有 ABI 目录。结果 APK 的 aapt 声明了三个 ABI，
        // x86_64 设备看到 lib/x86_64/ 就选它，启动时缺 libflutter.so →
        // UnsatisfiedLinkError（真机实测报告 E-01）。
        //
        // 过滤来源（按优先级）：
        // 1) `-PkeepsakeAbi=arm64|arm`（build-abis.cmd / CI 显式指定，最高优先）；
        // 2) Flutter 的 `-Ptarget-platform=android-arm64` 等——**这条以前缺了**，
        //    所以 README 里 `flutter build apk --release --target-platform android-arm64`
        //    会重新产出「声明 3 个 ABI、只带 arm64 引擎库」的必崩包（N-1）；
        // 3) 都没传（普通 `flutter build apk`）→ 交给 Flutter 的多 ABI 打包（此时
        //    三个 ABI 都有引擎库，是合法的）。
        val abiByTargetPlatform = mapOf(
            "android-arm64" to "arm64-v8a",
            "android-arm" to "armeabi-v7a",
            "android-x64" to "x86_64",
            "android-x86" to "x86",
        )
        val keepsakeAbi = (project.findProperty("keepsakeAbi") as String?)?.lowercase()
        val targetAbis = (project.findProperty("target-platform") as String?)
            ?.split(',')
            ?.mapNotNull { abiByTargetPlatform[it.trim()] }
            ?.distinct()
            ?.takeIf { it.isNotEmpty() }
        if (keepsakeAbi != null) {
            ndk {
                abiFilters.clear()
                abiFilters.add(
                    when (keepsakeAbi) {
                        "arm64" -> "arm64-v8a"
                        "arm" -> "armeabi-v7a"
                        else -> throw GradleException("未知识别 abi：$keepsakeAbi")
                    }
                )
            }
        } else if (targetAbis != null) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(targetAbis)
            }
        }
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
            // 不生成原生调试符号（`extractReleaseNativeSymbolTables`）。
            // 为什么关：我们不往 Play Console 传符号；而这个任务在 Windows 上
            // 偶发 `llvm-objcopy` 启动失败（本机 2026-11-24 出现过 3 次，
            // 重试有时好有时不好），关掉后构建稳定且产物一样能装。
            ndk {
                debugSymbolLevel = "none"
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
