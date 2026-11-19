import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.foehammer.console_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs this.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.foehammer.liquiflux"
        // Android 7.0: Shield, Google TV, and Fire TV on Fire OS 6 or later.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // tools/build-android.ps1 makes a signing key once, outside the source folder, and passes
    // its key.properties in LIQUIFLUX_KEY_PROPERTIES, so every build is signed the same way and
    // installs as an update over the last one. android/key.properties works too.
    val keyProps = Properties().apply {
        val f = System.getenv("LIQUIFLUX_KEY_PROPERTIES")?.let { file(it) } ?: rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    // The app-store build (flutter build apk -P liquiflux.store=amazon, with
    // --dart-define=LIQUIFLUX_STORE=amazon): src/store/AndroidManifest.xml takes out the
    // in-app updater's permission and the sleep timer's accessibility service. As the release
    // build type's manifest it outranks the main one, so its tools:node="remove" applies.
    if ((project.findProperty("liquiflux.store") as String?)?.isNotEmpty() == true) {
        sourceSets.getByName("release").manifest.srcFile("src/store/AndroidManifest.xml")
    }

    // The phone and tablet build (flutter build apk -P liquiflux.form=mobile, with
    // --dart-define=LIQUIFLUX_FORM=mobile; tools/build-android.ps1 -Mobile): its own manifest
    // in place of the TV one (rotation, picture-in-picture, Impeller, no leanback launcher or
    // sleep service). Same app id, so one store listing covers both; without the property the
    // build is the TV one, exactly as before.
    if (project.findProperty("liquiflux.form") == "mobile") {
        sourceSets.getByName("main").manifest.srcFile("src/mobile/AndroidManifest.xml")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Works around crashes with desugaring on Android 12L and later (flutter_local_notifications README).
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
}

flutter {
    source = "../.."
}
