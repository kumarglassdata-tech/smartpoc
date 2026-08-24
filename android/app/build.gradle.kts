plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.smartpoc.app.smartpoc"
    // The installed API 37 platform package is named "android-37.0" (new
    // X.Y versioning) but AGP looks up "android-37" - aliased by copying
    // sdk/platforms/android-37.0 to sdk/platforms/android-37. permission_handler_android
    // requires compileSdk >= 37, so this can't just be capped at 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.smartpoc.app.smartpoc"
        // MWDAT SDK requires minimum Android 10 (API 29)
        minSdk = 29
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["mwdat_application_id"] = "1397106792389839"
        manifestPlaceholders["mwdat_client_token"] = "AR|1397106792389839|b4974e0eaab94a57cbd68e7023ce904a"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("com.meta.wearable:mwdat-core:0.9.0")
    implementation("com.meta.wearable:mwdat-camera:0.9.0")
    implementation("com.meta.wearable:mwdat-mockdevice:0.9.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
