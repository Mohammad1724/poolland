import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing
//
// Credentials are resolved in this order:
//   1. android/key.properties          — local builds (git-ignored)
//   2. POOLLAND_KEYSTORE_* env vars    — CI, fed from GitHub Secrets
//   3. nothing                         — fall back to the debug key
//
// The debug fallback keeps `flutter run --release` and a fresh clone working,
// but a debug-signed APK is signed with a throwaway key that differs per
// machine, so users cannot upgrade over it ("App not installed") and it can
// never be published. See android/key.properties.example.
// ---------------------------------------------------------------------------
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun signingValue(fileKey: String, environmentKey: String): String? =
    (keystoreProperties.getProperty(fileKey) ?: System.getenv(environmentKey))
        ?.takeIf { it.isNotBlank() }

val keystorePath = signingValue("storeFile", "POOLLAND_KEYSTORE_PATH")
val keystorePassword = signingValue("storePassword", "POOLLAND_KEYSTORE_PASSWORD")
val keystoreAlias = signingValue("keyAlias", "POOLLAND_KEY_ALIAS")
val keystoreAliasPassword = signingValue("keyPassword", "POOLLAND_KEY_PASSWORD")

// `storeFile` may be absolute, relative to android/app/, or relative to android/.
val resolvedKeystore = keystorePath?.let { path ->
    listOf(file(path), rootProject.file(path)).firstOrNull { it.exists() }
}

val hasReleaseSigning = resolvedKeystore != null &&
    keystorePassword != null &&
    keystoreAlias != null &&
    keystoreAliasPassword != null

if (keystorePath != null && resolvedKeystore == null) {
    throw GradleException(
        "poolland: a release keystore was configured at '$keystorePath' but no " +
            "file exists there. Check storeFile in android/key.properties or " +
            "the POOLLAND_KEYSTORE_PATH environment variable."
    )
}

android {
    namespace = "com.poolland.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required for scheduled notifications (daily reminders).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.poolland.app"
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
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = resolvedKeystore
                storePassword = keystorePassword
                keyAlias = keystoreAlias
                keyPassword = keystoreAliasPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "poolland: no release keystore found, signing with the debug key. " +
                        "This APK cannot be upgraded in place by users or published. " +
                        "See android/key.properties.example."
                )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
