import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing material is never committed. Provide it either through
// environment variables (CI) or an ignored keystore.properties file (local).
val signingProperties = Properties().apply {
    val localFile = rootProject.file("keystore.properties")
    if (localFile.exists()) localFile.inputStream().use { load(it) }
}

fun signingValue(propertyKey: String, envKey: String): String? =
    System.getenv(envKey)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(propertyKey)?.takeIf { it.isNotBlank() }

android {
    namespace = "me.rain.mtforum"
    compileSdk = 36

    defaultConfig {
        applicationId = "me.rain.mtforum"
        minSdk = 33
        targetSdk = 36
        versionCode = 6
        versionName = "0.3.0"
    }

    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    signingConfigs {
        val releaseStorePath = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
        if (releaseStorePath != null) {
            create("release") {
                storeFile = file(releaseStorePath)
                storePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            // Signed with the stable release key when provided; otherwise a local
            // preview build falls back to the machine-local debug key.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    testImplementation("junit:junit:4.13.2")
}
