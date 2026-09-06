# KrKr2 Next — 开发文档（AI Agent 速查）

> 本目录面向 **AI Agent 与开发者**，用于快速掌握项目技术栈、架构与关键位置，
> 避免每次从头扫描整个代码库浪费上下文与 token。
> 请保持本目录内容与代码库现状同步；平台结构调整后务必更新。
>
> **新 AI Agent 上手顺序**：根目录 [AGENTS.md](../../AGENTS.md)（首屏指令）→ 本文档（索引）
> → [conventions.md](conventions.md)（约定与陷阱，最重要）→ [key-references.md](key-references.md)（关键文件/符号）。
> 本项目有大批量代码由 AI Agent 编写，请沿用本目录的文档约定并保持同步。

## 项目一句话

**KrKr2 Next**：KiriKiri2（吉里吉里2）视觉小说引擎的现代化运行环境。
C++ 引擎（TVP/TJS2）离屏渲染 → IOSurface / SurfaceTexture 零拷贝 → Flutter 纹理显示，
Flutter 壳应用提供 UI。当前**面向移动端**（iOS + Android 为主目标，macOS 为 Apple 开发目标）。

- 项目主页（本 fork）：<https://github.com/FiresonZ/KrKr2-Next-Mobile>（fork 自 KrKr2-Next 二次开发）
- 直接上游（fork 来源）：<https://github.com/reAAAq/KrKr2-Next>（基于 krkr2 源代码重构）
- 代码来源（重构基础）：<https://github.com/2468785842/krkr2>
- 许可证：GPL-3.0

## 目录索引

| 文档 | 内容 |
|------|------|
| [developers-guide.md](developers-guide.md) | **人类开发者入门**：30 分钟上手，核心概念/目录地图/代码路径/调试（先读这个） |
| [tech-stack.md](tech-stack.md) | 技术栈、语言、关键三方库、vcpkg 依赖 |
| [architecture.md](architecture.md) | 模块架构、渲染数据流、桥接层设计、GPU 管线现状 |
| [key-references.md](key-references.md) | 关键文件 / 符号 / C API 索引（改代码先看这里） |
| [build.md](build.md) | 构建与工具链（iOS / Android / macOS / Linux 验证）、产物、CI、排错 |
| [conventions.md](conventions.md) | 目录命名、平台约定、历史陷阱、SIMD 审计记录（重要） |
| [compatibility.md](compatibility.md) | 游戏兼容性测试方法论（与 Z 持平目标的闭环流程） |
| [perf-optimization.md](perf-optimization.md) | 性能优化与代码重构候选（收益/风险/验证方式） |
| [todo.md](todo.md) | **待办 / 已知问题（AI Agent 协作队列，先看这里）** |

## 极简速览（TL;DR）

```
apps/flutter_app/             Flutter 壳应用（ios / android / macos 平台目录）
bridge/engine_api/            C ABI 引擎桥接（engine_create/tick/destroy…）
bridge/flutter_engine_bridge/ Flutter 平台插件（IOSurface / SurfaceTexture + Dart FFI）
cpp/core/                     C++ 引擎核心（tjs2/base/environ/sound/visual/movie…）
cpp/plugins/                  TJS 插件（psb/psd/layerex/motionplayer/fstat/cubism…）
build.sh + build/*.sh         iOS / Android / macOS 一键构建
CMakeLists.txt + CMakePresets.json   MacOS/iOS/Android/Linux 预设
vcpkg.json + vcpkg/triplets/  arm64-ios / arm64-android 依赖与 triplet
platforms/apple/macos/        macOS 独立资源（Flutter 壳已接管入口）
```

**iOS 构建链路**：`./build.sh ios debug|release`
→ CMake iOS 预设编译 `libengine_api.a`（静态库）
→ `build_ios.sh` 用 `libtool` 合并工程/三方静态库到 `bridge/flutter_engine_bridge/ios/Libs/`
→ `flutter build ios`。

**Android 构建链路**：`./build.sh android debug|release`
→ CMake Android 预设编译 `libengine_api.so`（自包含共享库，含 JNI 胶水）
→ `build_android.sh` 拷贝到 `apps/flutter_app/android/app/src/main/jniLibs/arm64-v8a/`
→ `flutter build apk`。

**关键概念**：iOS 上引擎以**静态库**链接进 Runner，Dart 用 `DynamicLibrary.process()` 加载；
macOS 上为**动态库** `libengine_api.dylib`，打包进 App 的 Frameworks；
Android 上为**自包含 .so**（`-Wl,--whole-archive` 打包全部引擎目标），Dart FFI 直接加载。
详见 [architecture.md](architecture.md) 与 [build.md](build.md)。
