# build_rust_android.ps1
# Compiles the Rust core into Android native libraries (.so) for all ABIs.
#
# Prerequisites (run once):
#   1. Install Android NDK via Android Studio or standalone:
#        sdkmanager "ndk;27.0.12077973"
#   2. Install cargo-ndk:
#        cargo install cargo-ndk
#   3. Add Android Rust targets:
#        rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   4. Set ANDROID_NDK_HOME to your NDK path, e.g.:
#        $env:ANDROID_NDK_HOME = "C:\Users\CUBE\AppData\Local\Android\Sdk\ndk\27.0.12077973"

param(
    [ValidateSet("debug","release")]
    [string]$Profile = "debug"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RustCoreDir = Join-Path $ScriptDir "rust_core"
$JniLibsDir  = Join-Path $ScriptDir "flutter_app\android\app\src\main\jniLibs"

# ─── Sanity checks ───────────────────────────────────────────────────────────
if (-not (Get-Command "cargo" -ErrorAction SilentlyContinue)) {
    Write-Error "cargo not found. Install Rust from https://rustup.rs"
    exit 1
}
if (-not (Get-Command "cargo-ndk" -ErrorAction SilentlyContinue)) {
    Write-Error "cargo-ndk not found. Run: cargo install cargo-ndk"
    exit 1
}
if (-not $env:ANDROID_NDK_HOME -and -not $env:NDK_HOME) {
    Write-Warning "ANDROID_NDK_HOME is not set. cargo-ndk may fail to locate the NDK."
    Write-Warning "Set it with: `$env:ANDROID_NDK_HOME = 'C:\path\to\ndk\27.0.12077973'"
}

# ─── Build ───────────────────────────────────────────────────────────────────
Write-Host "Building rust_core for Android ($Profile)..." -ForegroundColor Cyan

Push-Location $RustCoreDir
try {
    $cargoArgs = @(
        "ndk",
        "-t", "arm64-v8a",
        "-t", "armeabi-v7a",
        "-t", "x86_64",
        "-o", $JniLibsDir,
        "build"
    )
    if ($Profile -eq "release") {
        $cargoArgs += "--release"
    }

    & cargo @cargoArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cargo ndk build failed (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}

# ─── Verify output ───────────────────────────────────────────────────────────
$expected = @(
    "$JniLibsDir\arm64-v8a\librust_core.so",
    "$JniLibsDir\armeabi-v7a\librust_core.so",
    "$JniLibsDir\x86_64\librust_core.so"
)

$allOk = $true
foreach ($f in $expected) {
    if (Test-Path $f) {
        $size = (Get-Item $f).Length
        Write-Host "  OK  $f  ($([math]::Round($size/1KB,1)) KB)" -ForegroundColor Green
    } else {
        Write-Warning "  MISSING  $f"
        $allOk = $false
    }
}

if ($allOk) {
    Write-Host "`nRust native libraries ready. You can now run:" -ForegroundColor Green
    Write-Host "  flutter run  (or  flutter build apk)" -ForegroundColor White
} else {
    Write-Warning "`nSome libraries are missing. Check the build output above."
}
