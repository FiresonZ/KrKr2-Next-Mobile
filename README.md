<p align="center">
  <h1 align="center">KrKr2 Next</h1>
  <p align="center">面向移动端的下一代 KiriKiri2（吉里吉里2）运行环境</p>
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

**语言 / Language**: 中文 | [English](README_EN.md)

> 🙏 本项目 **KrKr2 Next Mobile**（<https://github.com/FiresonZ/KrKr2-Next-Mobile>）是
> [KrKr2-Next](https://github.com/reAAAq/KrKr2-Next) 的 **fork 二次开发**；而 KrKr2-Next 基于
> [krkr2](https://github.com/2468785842/krkr2) 源代码重构。本项目的代码直接继承自 KrKr2-Next，
> 最终追溯至 krkr2，感谢上游作者们的贡献。

> 🤖 **AI Agent 协作说明**：本项目有大批量代码由 AI Agent 编写。新 AI Agent 请先阅读根目录
> [AGENTS.md](AGENTS.md)（首屏指令）与 [docs/dev/](docs/dev/README.md)（速查文档），再开始改代码。

## 简介

**KrKr2 Next** 是 [KiriKiri2 (吉里吉里2)](https://zh.wikipedia.org/wiki/%E5%90%89%E9%87%8C%E5%90%89%E9%87%8C2) 视觉小说引擎的现代化运行环境，**专注移动端：iOS + Android**（macOS 保留为 Apple 开发/调试目标）。它完全兼容原版游戏脚本，通过 ANGLE（iOS/macOS 用 Metal 后端，Android 用 Vulkan 后端）+ 零拷贝纹理共享（IOSurface / SurfaceTexture）实现硬件加速渲染，并在渲染性能与脚本执行效率上做了大量优化。

项目采用「C++ 引擎 + Flutter 壳」架构：C++ 引擎离屏渲染到 IOSurface（iOS/macOS）或 SurfaceTexture（Android），Flutter 以原生纹理零拷贝显示，UI 完全由 Flutter 构建。

## 架构

```
C++ 引擎 (cpp/core, TJS2) ──engine_api C ABI──> Dart FFI (flutter_engine_bridge)
        │ ANGLE EGL/GLES2 离屏渲染                     │ Flutter Texture
        └─ iOS/macOS: IOSurface ──┐                    │
        └─ Android:  SurfaceTexture ─┴──────────────────┘ 显示
```

- **渲染管线**：引擎通过 ANGLE 的 EGL Pbuffer Surface 离屏渲染（OpenGL ES 2.0），
  结果经 **IOSurface**（iOS/macOS）或 **SurfaceTexture**（Android）零拷贝传递给
  Flutter 纹理显示；CPU 回读（`engineReadFrameRgba`）作为兜底路径。
- **桥接层**：`bridge/engine_api` 提供稳定 C ABI（`engine_create` / `engine_tick` / `engine_destroy` 等）；
  iOS 以静态库链接进 Runner，Android 以 `libengine_api.so` 共享库打包进 APK；
  Dart 优先走 FFI，MethodChannel 为兜底。

> 📖 面向开发者/AI Agent 的完整技术文档见 **[docs/dev/](docs/dev/README.md)**（技术栈、架构、关键引用、构建、约定陷阱）。

## 平台支持

| 平台 | 状态 | 图形后端 | 纹理共享 | 引擎形态 |
|------|------|----------|----------|----------|
| iOS | 🚧 主目标，开发中 | Metal | IOSurface | 静态库链接进 Runner |
| Android | 🚧 主目标，开发中 | Vulkan | SurfaceTexture | `libengine_api.so` 打包进 APK |
| macOS | ✅ 开发目标 | Metal | IOSurface | dylib 打包进 Frameworks |

> 本地无 macOS 时：Android APK 可在 Windows 上直接构建；iOS 打包通过 GitHub Actions 的 macOS runner 完成。

## 系统要求

### iOS

| 项 | 要求 |
|----|------|
| 系统版本 | **iOS / iPadOS 15.0 及以上** |
| 架构 | 仅 64 位（**arm64**） |
| 设备 | iPhone 6s 及以上；iPad Air 2 / iPad mini 4 及以上；iPod touch（第 7 代） |
| 芯片 | A8 / A9 及以上（即所有支持 iOS 15 的 64 位设备） |

> 构建与运行链路（引擎静态库、vcpkg 依赖、Flutter）均按 `arm64`、部署目标 `iOS 15.0` 配置，
> 见 `CMakePresets.json`、`vcpkg/triplets/arm64-ios.cmake` 与 `ios/Podfile`。

### Android

| 项 | 要求 |
|----|------|
| 系统版本 | **Android 7.0（API 24）及以上** |
| 架构 | 仅 64 位（**arm64-v8a**） |
| 图形 | 支持 Vulkan 的 GPU（ANGLE Vulkan 后端） |

> 引擎按 `arm64-v8a`、API 24 配置（`vcpkg/triplets/arm64-android.cmake`）；
> 构建需 Android NDK（设置 `ANDROID_NDK_HOME`）。

## 构建

```bash
./build.sh ios release     # 构建 iOS（需 macOS/Xcode，或走 CI）
./build.sh android debug   # 构建 Android APK（Windows / macOS / Linux 均可）
./build.sh macos debug     # 构建 macOS（开发）
```

详见 [docs/dev/build.md](docs/dev/build.md) 与 [build.sh](build.sh)。

## CI 打包（GitHub Actions）

仓库内置在线打包工作流：

- **iOS**：[ios_package.yml](.github/workflows/ios_package.yml)（macOS runner）
- **Android**：[android_package.yml](.github/workflows/android_package.yml)（Ubuntu runner）

**触发方式**（两者一致）：
- 手动：Actions → 对应打包工作流 → Run workflow（可选 debug / release）
- 自动：推送 `v*` 标签（如 `v1.0.0`）

**产物**：
- iOS：`KrKr2-Next-iOS-<release|debug>.zip`（未签名的 `Runner.app`，保留 14 天）
- Android：`KrKr2-Next-Android-<release|debug>.apk`（保留 14 天）

**安装到真机**：
- iOS：下载 zip → 解压出 `Runner.app` → 用自己的 Apple 开发者证书签名
  （推荐用 Xcode 打开 `apps/flutter_app/ios/Runner.xcworkspace` 配置 Team 后运行），
  或用 `flutter run -d <device>` 开发调试。
- Android：直接安装 APK（`adb install` 或拷贝到手机点击安装）。

**首次构建**：vcpkg 需全量编译目标平台依赖（FFmpeg/OpenCV/ANGLE 等），耗时较长；
已启用 vcpkg 二进制缓存，后续运行秒级还原。

## CI 发布/版本号标准

主仓库用 GitHub Actions 手动触发即可**自动打 tag + 建 Release + 挂产物**，无需本地操作。

### 版本号（X.Y.Z 三段式）

- 格式：`主.次.修订`，如 `0.1.4`；递增修订号即可，主/次号在破坏性改动/新特性时递增。
- 一个版本号**同时控制**四处，保持一致：
  - Git tag / Release：`ios-vX.Y.Z`（iOS）、`android-vX.Y.Z`（Android），**分平台各自 Release**；
  - 原生 app 版本：iOS `CFBundleShortVersionString`、Android `versionName`（`--build-name`）；
  - 原生构建号：Android `versionCode`、iOS `CFBundleVersion`（`--build-number`），自动取
    `major*10000 + minor*100 + patch`（如 `0.1.4` → `104`）；
  - 软件内版本显示：设置 → 版本，副标题显示该版本号（`--dart-define=APP_VERSION` 注入）。

### 手动发布步骤（推荐）

1. Actions → 对应打包工作流 → Run workflow；
2. 填 `build_type=release`，填 **`发布版本号`**（`X.Y.Z`），勾选 **`发布 Release`**；
3. 跑完会自动：建 tag `ios-vX.Y.Z` / `android-vX.Y.Z` → 建对应 GitHub Release → 挂产物；
   - iOS 产物为**未签名 .ipa**，需自行用 Apple 证书签名侧载（AltStore / Sideloadly）；
   - Android 产物为 APK，直接安装（Android 7.0 / API 24+，arm64-v8a）。

> 只测不发布：不勾「发布 Release」即可，产物仍会以 workflow artifact 保留 14 天。
> 勾了发布但没填版本号（或格式不对）：构建前就报错中断，避免白等编译。
> 已存在的 tag 再次运行：不会重复建 Release，只会补充/覆盖上传该产物。
> 建议用 `release` 构建类型做正式发布；`debug` 仅用于测试，即使发布也是 debug 包。

### 参考

- 分平台 tag/Release 风格参考：
  <https://github.com/FiresonZ/mindustry-ios-builder/releases/tag/ios-v159.7>

## 开发进度

| 模块 | 状态 | 说明 |
|------|------|------|
| C++ 引擎核心编译 | ✅ 完成 | KiriKiri2 核心引擎可编译（iOS/Android/macOS） |
| ANGLE 渲染层迁移 | ✅ 基本完成 | EGL/GLES 离屏渲染（Metal / Vulkan 后端），替代旧 Cocos2d-x + GLFW 管线 |
| engine_api 桥接层 | ✅ 完成 | 稳定 C ABI，含启动/主循环/输入/内存统计等 |
| Flutter 插件（零拷贝纹理） | ✅ 基本完成 | IOSurface + SurfaceTexture 零拷贝纹理 + RGBA 兼容路径 |
| Flutter 调试 UI | ✅ 基本完成 | FPS 控制、引擎生命周期、渲染状态监控 |
| 输入事件转发 | ✅ 基本完成 | 触控 / 指针事件坐标映射转发 |
| Android 构建链 | 🔨 进行中 | vcpkg triplet、CMake preset、JNI 桥接、Kotlin 插件已接入，待真机验证 |
| 引擎性能优化 | 🔨 进行中 | SIMD 像素混合（Highway，已修复公式缺陷）、GPU 合成管线等 |
| 游戏兼容性优化 | 🔨 进行中 | 补全解析引擎、插件，目标与 Z 闭源版兼容持平 |

## 相关文档

- AI Agent 首屏指令：[AGENTS.md](AGENTS.md)
- 开发文档（AI Agent 速查）：[docs/dev/](docs/dev/README.md)
- 项目主页（本 fork）：<https://github.com/FiresonZ/KrKr2-Next-Mobile>
- 直接上游（fork 来源）：<https://github.com/reAAAq/KrKr2-Next>
- 代码来源（重构基础）：<https://github.com/2468785842/krkr2>

## 许可证

本项目基于 GNU General Public License v3.0 (GPL-3.0) 开源，详见 [LICENSE](./LICENSE)。
