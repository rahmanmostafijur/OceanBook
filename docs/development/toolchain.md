# Development toolchain (pinned)

Verified on 2026-10-01 on Windows 10 Pro 22H2 (10.0.19045). CI uses the same pins.

## Versions

| Tool | Version | Source | Notes |
|------|---------|--------|-------|
| Flutter | **3.47.5** (stable), framework 6a19cca564, engine af7e796e16 | Official archive `flutter_windows_3.47.5-stable.zip`, SHA-256 `0ccd71931f49c2fbe394b1eeb6d79af3d624058a043ea0d03d34160581624fb8`, from `storage.googleapis.com/flutter_infra_release` | Stable channel only; never `beta`/`main`. Upgrade deliberately: change this file, CI and `environment` constraints together |
| Dart | **3.13.4** (stable) | Bundled with Flutter | `environment.sdk: ^3.13.4` in every pubspec |
| DevTools | 2.60.0 | Bundled | |
| JDK | **17.0.20.1 LTS** (Microsoft Build of OpenJDK) | `winget install Microsoft.OpenJDK.17` | `flutter config --jdk-dir` points at it; Gradle/AGP for Flutter 3.47 run on JDK 17 |
| Android SDK command-line tools | 15859902 (`commandlinetools-win-15859902_latest.zip`, SHA-256 `90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a`) | `dl.google.com/android/repository` | Installed under `ANDROID_HOME/cmdline-tools/latest` |
| Android platform | **android-36** | `sdkmanager` | = Flutter 3.47.5 `compileSdkVersion` / `targetSdkVersion` |
| Android build-tools | **36.1.0** | `sdkmanager` | |
| Android NDK | **28.2.13676358** | `sdkmanager` | = Flutter 3.47.5 `ndkVersion` (installed up front for reproducible builds) |
| Android platform-tools | latest at install time | `sdkmanager` | `adb` |
| minSdk | 24 | Flutter 3.47.5 default | Android 7.0+ |
| Chrome | 154.0.8037.58 | Pre-installed | Web target and web tests |
| Edge | 154.0.4258.48 | Pre-installed | Secondary web device |
| Python / uv | 3.13.12 / uv 0.10.7 | Backend (see backend/README.md) | |
| Docker | 29.6.1 | Docker Desktop | PostgreSQL 18 + Valkey 8 for integration tests |

## Deliberately not installed

- **Android Studio (IDE):** building and testing only need the SDK and a JDK, both installed headlessly with Google's official command-line tools. `flutter doctor` is green for the Android toolchain without it. Install it if you want the IDE or the emulator UI; nothing in the build depends on it.
- **Android Emulator / system images:** not needed for builds or tests. Add with `sdkmanager "emulator" "system-images;android-36;google_apis;x86_64"` when needed.
- **Visual Studio (C++ desktop workload):** only for Windows desktop apps, which OceanBook does not target. Desktop targets are disabled (`flutter config --no-enable-windows-desktop --no-enable-linux-desktop --no-enable-macos-desktop`).
- **Xcode / iOS toolchain:** requires macOS. iOS builds and tests run on a macOS CI runner.

## Machine setup (Windows)

```powershell
# Flutter (verify the SHA-256 above before extracting)
Expand-Archive flutter_windows_3.47.5-stable.zip D:\dev
# JDK
winget install --id Microsoft.OpenJDK.17 --exact
# Android SDK (command-line tools zip extracted to D:\dev\android-sdk\cmdline-tools\latest)
sdkmanager --sdk_root=D:\dev\android-sdk --licenses
sdkmanager --sdk_root=D:\dev\android-sdk "platform-tools" "platforms;android-36" "build-tools;36.1.0" "ndk;28.2.13676358"
# Environment (user scope): JAVA_HOME, ANDROID_HOME=D:\dev\android-sdk,
# PATH += D:\dev\flutter\bin; D:\dev\android-sdk\platform-tools; %JAVA_HOME%\bin
flutter config --enable-web --android-sdk D:\dev\android-sdk --jdk-dir "C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
flutter doctor -v
```

## Verification record (2026-10-01)

- `flutter doctor -v`: Flutter ✓, Android toolchain ✓ (SDK 36.1.0, all licenses accepted, JDK 17.0.20.1), Chrome ✓, network ✓. The only issue is Visual Studio (not applicable; see above).
- `flutter devices`: Chrome (web), Edge (web).
- `flutter build web --release` (apps/admin, M9 code): ✓
- `flutter build apk --debug` (apps/mobile, M8 code): ✓ (`app-debug.apk`, about 196 MB; Gradle assembleDebug takes about 47 s warm)
- CI: [.github/workflows/flutter.yml](../../.github/workflows/flutter.yml) pins the same Flutter version and runs format, `analyze --fatal-infos` and tests on every member, then the web and APK builds. actionlint is clean.
