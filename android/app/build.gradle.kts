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
        versionCode = 1000 + (System.getenv("GITHUB_RUN_NUMBER") ?: "0").toInt()  // eski depodaki sürümlerden büyük olsun
        versionName = "1.0." + (System.getenv("GITHUB_RUN_NUMBER") ?: "0")
    }

    // İmza anahtarı GitHub Secrets'tan gelir (depoda anahtar yok).
    // Hep aynı anahtar: yeni sürümler eskisinin ÜSTÜNE kurulur.
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("KEYSTORE_FILE") ?: "odak.p12")
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            keyAlias = "odak"
            keyPassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            storeType = "PKCS12"
        }
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
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
