import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("../key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// 判定 release 签名是否真的可用。
//
// key.properties 里只记录了 storeFile 的**路径**，文件本身不在仓库里。
// 远端 / CI 构建机上通常没有这份私钥，如果照样把签名配置指向它，
// `:app:validateSigningRelease` 会直接让整个构建失败：
//   Keystore file '/root/mtforum-release.keystore' not found
// 所以这里先探测文件是否存在，不存在就回落到 debug 签名，
// 让 release 构建仍然能产出可安装的 APK（只是不能覆盖已安装的正式签名版本）。
val releaseKeystorePath: String? = keystoreProperties
    .getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
val releaseKeystore: File? = releaseKeystorePath?.let { file(it) }
val hasReleaseKeystore: Boolean = releaseKeystore?.exists() == true

if (!hasReleaseKeystore) {
    logger.warn(
        "MTForum: 未找到 release 签名文件（storeFile=${releaseKeystorePath ?: "未配置"}）。" +
            "本次 release 构建将使用 debug 签名；如需正式签名，请把 keystore 放到该路径，" +
            "或在构建环境提供 key.properties 与私钥。"
    )
}

android {
    namespace = "com.binmt.mtforum"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.binmt.mtforum"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // 仅当 key.properties 与 keystore 文件都真实存在时才配置签名。
            if (hasReleaseKeystore) {
                storeFile = releaseKeystore
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 没有正式私钥时回落到 debug 签名，避免 validateSigningRelease 失败。
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
