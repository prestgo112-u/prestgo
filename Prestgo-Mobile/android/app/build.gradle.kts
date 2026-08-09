import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase : à réactiver en même temps que le dépôt de `google-services.json`.
    // Tant qu'aucun fournisseur FCM n'est configuré (R6), le greffon ferait échouer la
    // compilation. `Firebase.initializeApp(options: ...)` fonctionne sans lui.
    // id("com.google.gms.google-services")
}

android {
    namespace = "test.prestgo.prestgo_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Exigé par flutter_local_notifications (API de date/heure du JDK 8+).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "test.prestgo.prestgo_mobile"
        // Plancher imposé par firebase_messaging, flutter_secure_storage (chiffrement
        // moderne) et geolocator — cf. R13 de research.md.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Trois saveurs alignées sur env/{dev,staging,prod}.json (R4).
    flavorDimensions += "environnement"

    productFlavors {
        create("dev") {
            dimension = "environnement"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "PRESTGO dev")
            // Le trafic en clair est autorisé **pour cette saveur seulement** : le
            // service de développement est servi en HTTP sur 10.0.2.2.
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        create("staging") {
            dimension = "environnement"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "PRESTGO staging")
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
        create("prod") {
            dimension = "environnement"
            resValue("string", "app_name", "PRESTGO")
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
    }

    // Signature de livraison (T248) : clés lues dans `android/key.properties`
    // (jamais versionné — cf. android/.gitignore). Sans ce fichier, la clé de
    // débogage prend le relais : `flutter run --release` et l'intégration
    // continue fonctionnent sans secret, mais l'APK produit n'est pas publiable.
    //
    // Format attendu de key.properties :
    //   storeFile=<chemin du keystore>
    //   storePassword=…
    //   keyAlias=…
    //   keyPassword=…
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties().apply {
        if (keystorePropertiesFile.exists()) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
