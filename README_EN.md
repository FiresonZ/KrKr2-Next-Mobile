<p align="center">
  <h1 align="center">KrKr2 Next</h1>
  <p align="center">A Next-Generation KiriKiri2 Runtime for Mobile (iOS + Android)</p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-In%20Development-orange" alt="Status">
  <img src="https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/engine-KiriKiri2-blue" alt="Engine">
  <img src="https://img.shields.io/badge/framework-Flutter-02569B" alt="Flutter">
  <img src="https://img.shields.io/badge/graphics-ANGLE(Metal%2FVulkan)-red" alt="Graphics">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License">
</p>

---

**Language / 语言**: [中文](README.md) | English

> 🙏 This project, **KrKr2 Next Mobile** (<https://github.com/FiresonZ/KrKr2-Next-Mobile>), is a
> **fork-based secondary development** of [KrKr2-Next](https://github.com/reAAAq/KrKr2-Next),
> which is itself a refactor built on the source code of [krkr2](https://github.com/2468785842/krkr2).
> This project's code is inherited directly from KrKr2-Next and ultimately traces back to krkr2.
> Thanks to all upstream authors.

> 🤖 **AI-agent collaboration note**: a large portion of this project's code was written by AI agents.
> A new AI agent should start by reading [AGENTS.md](AGENTS.md) (first-screen instructions) and
> [docs/dev/](docs/dev/README.md) (quick-reference docs) before touching any code.

## Overview

**KrKr2 Next** is a modern runtime for the [KiriKiri2](https://en.wikipedia.org/wiki/KiriKiri) visual novel engine, **focused on mobile: iOS + Android** (macOS is kept as the Apple development/debug host). It is fully compatible with original game scripts, uses ANGLE (Metal backend on iOS/macOS, Vulkan backend on Android) with zero-copy texture sharing (IOSurface / SurfaceTexture) for hardware-accelerated rendering, and includes numerous optimizations for both rendering performance and script execution.

The project follows a "C++ engine + Flutter shell" architecture: the C++ engine renders offscreen to an IOSurface (iOS/macOS) or SurfaceTexture (Android), Flutter displays it via a native texture with zero-copy transfer, and the UI is fully built with Flutter.

## Architecture

```
C++ Engine (cpp/core, TJS2) ──engine_api C ABI──> Dart FFI (flutter_engine_bridge)
        │ ANGLE EGL/GLES2 offscreen                  │ Flutter Texture
        └─ iOS/macOS: IOSurface ──┐                  │
        └─ Android:  SurfaceTexture ─┴────────────────┘ display
```

- **Rendering pipeline**: the engine renders offscreen via ANGLE's EGL Pbuffer Surface (OpenGL ES 2.0);
  the result is passed to a Flutter texture through **IOSurface** (iOS/macOS) or **SurfaceTexture** (Android)
  with zero-copy transfer; CPU readback (`engineReadFrameRgba`) is the fallback path.
- **Bridge layer**: `bridge/engine_api` exposes a stable C ABI (`engine_create` / `engine_tick` / `engine_destroy`, etc.);
  iOS links it as a static library into the Runner, Android ships it as `libengine_api.so` inside the APK;
  Dart prefers FFI, with MethodChannel as a fallback.

> 📖 Full developer/AI-agent documentation: **[docs/dev/](docs/dev/README.md)** (tech stack, architecture, key references, build, conventions).

## Platform Support

| Platform | Status | Graphics Backend | Texture Sharing | Engine Binary |
|----------|--------|------------------|-----------------|---------------|
| iOS | 🚧 Primary target, in development | Metal | IOSurface | Static library linked into Runner |
| Android | 🚧 Primary target, in development | Vulkan | SurfaceTexture | `libengine_api.so` packaged into APK |
| macOS | ✅ Development target | Metal | IOSurface | dylib bundled into Frameworks |

> No macOS locally? Build the Android APK directly on Windows; package iOS through the GitHub Actions macOS runner.

## System Requirements

### iOS

| Item | Requirement |
|------|-------------|
| OS version | **iOS / iPadOS 15.0 or later** |
| Architecture | 64-bit (**arm64**) only |
| Devices | iPhone 6s or later; iPad Air 2 / iPad mini 4 or later; iPod touch (7th gen) |
| Chip | A8 / A9 or later (i.e. all 64-bit devices that support iOS 15) |

> The whole build/run chain (engine static library, vcpkg deps, Flutter) is configured for
> `arm64` with deployment target `iOS 15.0` — see `CMakePresets.json`,
> `vcpkg/triplets/arm64-ios.cmake` and `ios/Podfile`.

### Android

| Item | Requirement |
|------|-------------|
| OS version | **Android 7.0 (API 24) or later** |
| Architecture | 64-bit (**arm64-v8a**) only |
| Graphics | Vulkan-capable GPU (ANGLE Vulkan backend) |

> The engine is configured for `arm64-v8a`, API 24 (see `vcpkg/triplets/arm64-android.cmake`);
> building requires the Android NDK (set `ANDROID_NDK_HOME`).

## Build

```bash
./build.sh ios release     # Build iOS (requires macOS + Xcode, or use CI)
./build.sh android debug   # Build Android APK (any host: Windows / macOS / Linux)
./build.sh macos debug     # Build macOS (development)
```

See [docs/dev/build.md](docs/dev/build.md) and [build.sh](build.sh).

## CI Packaging (GitHub Actions)

Built-in packaging workflows:

- **iOS**: [ios_package.yml](.github/workflows/ios_package.yml) (macOS runner)
- **Android**: [android_package.yml](.github/workflows/android_package.yml) (Ubuntu runner)
- **Engine-core verification (Linux)**: [engine_verify.yml](.github/workflows/engine_verify.yml)
  (host build + tests, triggered on every push/PR — the fastest feedback loop)

**Trigger** (packaging workflows):
- Manual: Actions → pick the workflow → Run workflow (choose debug / release)
- Automatic: push a `v*` tag (e.g. `v1.0.0`)

**Artifacts**:
- iOS: `KrKr2-Next-iOS-<release|debug>.zip` (unsigned `Runner.app`, kept for 14 days)
- Android: `KrKr2-Next-Android-<release|debug>.apk` (kept for 14 days)

**Install on device**:
- iOS: download the zip → extract `Runner.app` → sign with your own Apple developer certificate
  (recommended: open `apps/flutter_app/ios/Runner.xcworkspace` in Xcode, set your Team, then run),
  or use `flutter run -d <device>` for development.
- Android: install the APK directly (`adb install` or copy to the phone).

**First build**: vcpkg must fully compile the target-platform dependencies
(FFmpeg/OpenCV/ANGLE, etc.), which takes a while; vcpkg binary caching is enabled,
so subsequent runs restore dependencies quickly.

## Development Progress

| Module | Status | Notes |
|--------|--------|-------|
| C++ Engine Core Build | ✅ Done | KiriKiri2 core engine compiles (iOS/Android/macOS) |
| ANGLE Rendering Migration | ✅ Mostly Done | EGL/GLES offscreen rendering (Metal / Vulkan backends) |
| engine_api Bridge Layer | ✅ Done | Stable C ABI: startup, main loop, input, memory stats, etc. |
| Flutter Plugin (zero-copy textures) | ✅ Mostly Done | IOSurface + SurfaceTexture + RGBA fallback path |
| Flutter Debug UI | ✅ Mostly Done | FPS control, engine lifecycle, rendering monitor |
| Input Event Forwarding | ✅ Mostly Done | Touch / pointer coordinate mapping and forwarding |
| Android build chain | 🔨 In Progress | triplet / CMake preset / JNI bridge / Kotlin plugin wired, awaiting device verification |
| Engine Performance | 🔨 In Progress | SIMD pixel blending (Highway, formula defects fixed), GPU compositing pipeline, etc. |
| Game Compatibility | 🔨 In Progress | Completing the script parser and plugins; target parity with Z's closed-source build |

## Related Docs

- AI-agent first-screen instructions: [AGENTS.md](AGENTS.md)
- Development docs (AI-agent quick reference): [docs/dev/](docs/dev/README.md)
- Project home (this fork): <https://github.com/FiresonZ/KrKr2-Next-Mobile>
- Direct upstream (fork source): <https://github.com/reAAAq/KrKr2-Next>
- Code source (refactor base): <https://github.com/2468785842/krkr2>

## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See [LICENSE](./LICENSE) for details.
