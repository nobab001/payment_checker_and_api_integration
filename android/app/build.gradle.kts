plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Must match android/app/google-services.json + MainActivity package.
    namespace = "com.example.payment_checker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion  // Firebase requires 21+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Two installable apps on one device (distinct entry points: main_user vs main_admin).
    flavorDimensions += "default"
    productFlavors {
        create("user") {
            dimension = "default"
            applicationId = "com.yourdomain.userapp"
            resValue("string", "app_name", "User App")
        }
        create("admin") {
            dimension = "default"
            applicationId = "com.yourdomain.adminapp"
            resValue("string", "app_name", "Admin App")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
