plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.odakkilidi.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.odakkilidi.app"
        minSdk = 26
        targetSdk = 34
        // Her GitHub derlemesinde sürüm numarası otomatik artar (güncelleme üstüne kurulabilsin diye)
        versionCode = (System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()
        versionName = "1.0." + (System.getenv("GITHUB_RUN_NUMBER") ?: "0")
    }

    // Sabit imza anahtarı: yeni sürümler eskisinin ÜSTÜNE kurulur, silmek gerekmez.
    signingConfigs {
        create("release") {
            storeFile = file("odak.jks")
            storePassword = "odakkilidi"
            keyAlias = "odak"
            keyPassword = "odakkilidi"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}
