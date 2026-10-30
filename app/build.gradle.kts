import java.io.File

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// ===== release 签名 =====
// 本机写死 rain.jks 路径；CI 通过环境变量 ANDROID_KEYSTORE_PATH 覆盖。
// 私钥本身不入库（.gitignore 已忽略 *.jks / *.keystore / *.p12）。
val localKeystorePath = "/home/evo/projects/key/rain.jks"
val localStorePassword = "fycnb666"
val localKeyAlias = "rain"
val localKeyPassword = "fycnb666"

fun resolveKeystore(): File? {
    val fromEnv = System.getenv("ANDROID_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
    if (fromEnv != null) return file(fromEnv)
    val candidates = listOf(file(localKeystorePath), rootProject.file("rain.jks"), file("../rain.jks"))
    return candidates.firstOrNull { it.isFile }
}

fun signingSecret(envKey: String, localValue: String): String =
    System.getenv(envKey)?.takeIf { it.isNotBlank() } ?: localValue

// 仅本地预览时可用 -PallowDebugSigning 绕过缺钥报错
val allowDebugSigning: Boolean = project.hasProperty("allowDebugSigning")

android {
    namespace = "me.rain.mtforum"
    compileSdk = 36

    defaultConfig {
        applicationId = "me.rain.mtforum"
        minSdk = 33
        targetSdk = 36
        versionCode = 11
        versionName = "0.3.5"
    }

    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        val keystore = resolveKeystore()
        if (keystore != null) {
            create("release") {
                storeFile = keystore
                storePassword = signingSecret("ANDROID_STORE_PASSWORD", localStorePassword)
                keyAlias = signingSecret("ANDROID_KEY_ALIAS", localKeyAlias)
                keyPassword = signingSecret("ANDROID_KEY_PASSWORD", localKeyPassword)
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning == null) {
                if (!allowDebugSigning) {
                    throw GradleException(
                        "找不到 release 签名密钥：请确认 $localKeystorePath 存在，" +
                            "或设置 ANDROID_KEYSTORE_PATH；仅做本地预览可加 -PallowDebugSigning"
                    )
                }
                logger.warn("⚠ 未找到 rain.jks，release 使用 debug 签名（-PallowDebugSigning，勿用于发布）")
            }
            signingConfig = releaseSigning ?: signingConfigs.getByName("debug")
        }
    }
    lint { abortOnError = true }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("androidx.datastore:datastore-preferences:1.1.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("androidx.compose.ui:ui:1.9.3")
    implementation("androidx.compose.foundation:foundation:1.9.3")
    implementation("androidx.compose.animation:animation:1.9.3")
    implementation("top.yukonga.miuix.kmp:miuix-android:0.7.2")
    // Kyant0/AndroidLiquidGlass (Backdrop). 1.0.0 targets Kotlin 2.2.21.
    implementation("io.github.kyant0:backdrop:1.0.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jsoup:jsoup:1.18.3")
    implementation("io.coil-kt:coil-compose:2.7.0")
    implementation("com.google.zxing:core:3.5.4")
    testImplementation("junit:junit:4.13.2")
}
