# 构建与工具链

> iOS 构建需在 **macOS** 上进行（需要 Xcode + Apple 工具链 + vcpkg）。
> **Android 构建可在 Windows / macOS / Linux 上进行**（需要 NDK + vcpkg）。
> 根 CMake 设置 `CMAKE_TOOLCHAIN_FILE=$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake`，依赖由 vcpkg manifest 安装。

## 前置要求

### iOS / macOS（macOS 主机）

- macOS（Apple Silicon 或 Intel）+ Xcode

- CMake ≥3.28、Ninja、ccache（可选）

- bison（TJS2 parser 生成，Homebrew：`/opt/homebrew/opt/bison`）

- **autoconf / automake / autoconf-archive / libtool / gettext / pkg-config**
  （vcpkg 交叉编译 iOS 时需构建宿主工具：gperf→glib、libexif 等 autotools 端口；
  GNU libtool 提供 `libtool.m4` 供 aclocal 使用）

  ```bash
  brew install cmake ninja bison autoconf automake autoconf-archive libtool gettext pkg-config
  ```

  > ⚠️ Homebrew 的 GNU libtool 会覆盖 PATH 里的 `libtool`。
  > `build_ios.sh` 已改为显式调用系统 `/usr/bin/libtool` 做静态库合并（`-static`），勿改回裸 `libtool`。

### Android（任意主机）

- Android NDK（r25+ 推荐），设置环境变量：
  ```bash
  export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/<版本>"   # Windows: set ANDROID_NDK_HOME=...
  ```
  > `build_android.sh` 会自动从 `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` / `$ANDROID_HOME/ndk/*`（取最新）定位 NDK。

- JDK 17（AGP 8 要求，Android Studio 自带）

- CMake ≥3.28、Ninja

- Flutter SDK（`flutter` 在 PATH，或放到 `.devtools/flutter`）——`flutter doctor --android-licenses` 需通过

- 网络（vcpkg 首次会 clone 依赖）

## 快速开始

```bash
# 一键构建 iOS（默认 debug，需 macOS）
./build.sh ios debug

# 或 release
./build.sh ios release

# Android APK（Windows / macOS / Linux 均可）
./build.sh android debug

# macOS
./build.sh macos debug
```

## iOS 构建步骤（build/build\_ios.sh 内部）

1. 定位 Flutter SDK（`.devtools/flutter` 或 PATH）。
2. 定位/自举 vcpkg（`.devtools/vcpkg`，`bootstrap-vcpkg.sh`）。
3. CMake 配置 `iOS <Debug|Release> Config` 预设 → 构建 `iOS <Debug|Release> Build`。

   - 输出：`out/ios/<type>/bridge/engine_api/libengine_api.a`（静态库）

   - 依赖装到 `out/ios/<type>/vcpkg_installed/arm64-ios/`（triplet `arm64-ios`）
4. **静态库合并**：

   - 工程库（排除 `cpp/plugins` 顶层，保留深层子库如 psdparse 的独有 `.o`）→ `libengine_project.a`

   - vcpkg 三方库（排除 libpng/libjpeg/libwebpdecoder/libharfbuzz-subset 冗余子集）→ `libengine_vendors.a`

   - 二者写入 `bridge/flutter_engine_bridge/ios/Libs/`（该目录 `*.a` 已 gitignore）
5. `flutter pub get` + `flutter build ios --<mode> --no-codesign`

   - 产物：`apps/flutter_app/build/ios/iphoneos/Runner.app`
6. 真机运行：Xcode 打开 `apps/flutter_app/ios/Runner.xcworkspace`。

## macOS 构建步骤（build/build\_macos.sh 内部）

1. CMake `MacOS <Debug|Release> Config` → 构建 → `out/macos/<type>/bridge/engine_api/libengine_api.dylib`。
2. `flutter build macos --<mode>` → `build/macos/Build/Products/<Debug|Release>/KrKr2 Next.app`。
3. 把 dylib 拷入 `Contents/Frameworks/`，`install_name_tool` 设 `@executable_path/../Frameworks/`，ad-hoc 重签。

## Android 构建步骤（build/build\_android.sh 内部）

1. 定位 NDK（`ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` / `$ANDROID_HOME/ndk/*` 最新版）。
2. 定位 Flutter SDK（`.devtools/flutter` 或 PATH）。
3. 定位/自举 vcpkg（`.devtools/vcpkg`，`bootstrap-vcpkg.sh`）。
4. CMake 配置 `Android <Debug|Release> Config` 预设 → 构建 `Android <Debug|Release> Build`。

   - 输出：`out/android/<type>/bridge/engine_api/libengine_api.so`（**自包含共享库**）

   - 依赖装到 `out/android/<type>/vcpkg_installed/arm64-android/`（triplet `arm64-android`）

   - `engine_api` 通过 `-Wl,--whole-archive` 打包全部引擎目标（等价 iOS 的 `-force_load`）；
     JNI 胶水 `engine_api_android_jni.cpp` 提供 `krkr_GetNativeWindow` 及 Kotlin 可调用的
     `nativeSetSurface` / `nativeDetachSurface`。
5. 拷贝 `libengine_api.so` → `apps/flutter_app/android/app/src/main/jniLibs/arm64-v8a/`（已 gitignore）。
6. `flutter pub get` + `flutter build apk --<mode>`。

   - 产物：`apps/flutter_app/build/app/outputs/flutter-apk/app-<debug|release>.apk`
7. 真机运行：`flutter run -d <device>`（或 `adb install` APK）。

### Android 渲染路径

- **GPU 零拷贝（首选）**：Kotlin 插件 `createSurfaceTexture` 创建 `SurfaceTexture` → JNI
  `nativeSetSurface` 把 `ANativeWindow` 交给引擎 → `engine_tick` 自动挂载 EGL WindowSurface
  （ANGLE Vulkan 后端）→ `eglSwapBuffers` 直接把帧交给 Flutter。
- **CPU 回读（兜底）**：`engineReadFrameRgba` → Dart → `updateTextureRgba` → FlutterTexture 上传。
- 若 SurfaceTexture 创建失败，`engine_surface.dart` 会自动降级到回读路径。

## 产物路径速查

| 目标    | 引擎库                                                               | App 产物                                                                       |
| ----- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| iOS   | `out/ios/{debug,release}/bridge/engine_api/libengine_api.a`       | `apps/flutter_app/build/ios/iphoneos/Runner.app`                             |
| Android | `out/android/{debug,release}/bridge/engine_api/libengine_api.so` | `apps/flutter_app/build/app/outputs/flutter-apk/app-{debug,release}.apk`      |
| macOS | `out/macos/{debug,release}/bridge/engine_api/libengine_api.dylib` | `apps/flutter_app/build/macos/Build/Products/{Debug,Release}/KrKr2 Next.app` |

## 常用操作

```bash
# 清理某平台产物
./build.sh --clean ios
./build.sh --clean android
./build.sh --clean macos

# 并行数
JOBS=16 ./build.sh ios release
```

## CI 打包（GitHub Actions）

- **iOS**：`.github/workflows/ios_package.yml`（手动触发或 `v*` 标签），运行于 `macos-15`。

- **Android**：`.github/workflows/android_package.yml`（手动触发或 `v*` 标签），运行于 `ubuntu-22.04`：
  setup Flutter + JDK 17 + 自动安装 NDK（`sdkmanager "ndk;27.0.12077973"`）+ `./build.sh android <type>`。

- **引擎核心验证（Linux）**：`.github/workflows/engine_verify.yml`（push/PR 自动触发），
  运行于 `ubuntu-22.04`：以宿主构建（`Linux Debug` 预设，`x64-linux` triplet）编译引擎核心 +
  tools，跑 ctest（tests/ 目录，目前为空）+ `tools/xp3 --help` 冒烟。
  这是最快的反馈闭环（5-10 分钟），后续 SIMD 逐像素比对等测试挂这里。

- vcpkg 二进制缓存：`~/.cache/vcpkg`（key 基于 `vcpkg.json`/`vcpkg-configuration.json`/`vcpkg/**`），
  通过环境变量 `VCPKG_BINARY_SOURCES=files,<path>,readwrite` 启用。

- iOS 产物：未签名 `Runner.app` 的 zip（`ditto` 打包）；Android 产物：APK。均保留 14 天。

- iOS 真机安装需自行用 Apple 开发者证书签名；Android 可直接安装 APK。

## 常见问题

- **找不到 bison**：Homebrew 安装后路径在 `HINTS` 里已列（tjs2/CMakeLists.txt）。

- **vcpkg 卡住**：首次安装 `arm64-ios` 依赖耗时长；`--jobs` 控制并行。

- **符号找不到（iOS）**：确认 `build_ios.sh` 的 libtool 合并步骤成功，`ios/Libs/*.a` 已更新，
  且 Runner 链接了这些库（podspec 配置）。

- **静态库重复符号**：多为冗余三方库未排除（libpng/libjpeg/libwebpdecoder 等），核对合并脚本排除列表。

