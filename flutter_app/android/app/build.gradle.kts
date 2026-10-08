plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hifi.flutter_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hifi.flutter_app"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main") {
            // Pre-built Rust native libraries are placed here by build_rust.ps1
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}

// ─── Rust Native Library Build ───────────────────────────────────────────────
// Requires: cargo-ndk installed (`cargo install cargo-ndk`), Android NDK,
// and the Android Rust targets added via rustup.
// Run `.\build_rust.ps1` from the project root before `flutter build apk`.
// Gradle will also invoke the build automatically via the task below.

val rustCoreDir = file("${rootDir}/../../rust_core")
val jniLibsDir = file("${projectDir}/src/main/jniLibs")

val buildRustDebug by tasks.registering(Exec::class) {
    workingDir(rustCoreDir)
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a",
        "-t", "armeabi-v7a",
        "-o", jniLibsDir.absolutePath,
        "build"
    )
    isIgnoreExitValue = true // Don't fail the build if cargo-ndk is absent
}

val buildRustRelease by tasks.registering(Exec::class) {
    workingDir(rustCoreDir)
    commandLine(
        "cargo", "ndk",
        "-t", "arm64-v8a",
        "-t", "armeabi-v7a",
        "-o", jniLibsDir.absolutePath,
        "build", "--release"
    )
    isIgnoreExitValue = true
}

afterEvaluate {
    tasks.named("preDebugBuild") { dependsOn(buildRustDebug) }
    tasks.named("preReleaseBuild") { dependsOn(buildRustRelease) }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.media3:media3-session:1.3.1")
    implementation("androidx.media3:media3-exoplayer:1.3.1")
    implementation("androidx.palette:palette-ktx:1.0.0")

    // yt-dlp bundled for Android — same library used by YTDLnis
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    // FFmpeg for post-processing (audio extraction, format conversion)
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.17.2")
}

flutter {
    source = "../.."
}
