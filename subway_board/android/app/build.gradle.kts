import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.arunvijey.subwayboard"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications needs java.time on older Android versions.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.arunvijey.subwayboard"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // A side-by-side preview build (`--android-project-arg=preview=true`):
        // its own app id and name, so it never touches the installed app's data.
        val preview = project.hasProperty("preview")
        if (preview) applicationIdSuffix = ".preview"
        manifestPlaceholders["appLabel"] = if (preview) "Board β" else "Subway Board"

        // `flutter build apk --target-platform android-arm64` only puts Flutter's
        // own engine in for that CPU; plugins' native libraries still came in for
        // every CPU. Keep just the ones the build is for.
        val abis = (project.findProperty("target-platform") as String?)
            ?.split(',')
            ?.mapNotNull { mapOf("android-arm64" to "arm64-v8a", "android-arm" to "armeabi-v7a", "android-x64" to "x86_64")[it.trim()] }
            .orEmpty()
        if (abis.isNotEmpty() && !project.hasProperty("split-per-abi")) ndk { abiFilters += abis }
    }

    packaging {
        resources {
            // Library licence texts and Kotlin reflection metadata the app never reads.
            excludes += listOf("META-INF/**/LICENSE*", "kotlin/**.kotlin_builtins", "DebugProbesKt.bin")
        }
    }

    signingConfigs {
        create("release") {
            // Credentials live in android/key.properties (gitignored).
            val keyProps = Properties()
            val keyPropsFile = rootProject.file("key.properties")
            if (keyPropsFile.exists()) {
                keyPropsFile.inputStream().use { keyProps.load(it) }
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Fall back to the debug key when key.properties is absent (e.g. fresh clone).
            signingConfig = if (rootProject.file("key.properties").exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
