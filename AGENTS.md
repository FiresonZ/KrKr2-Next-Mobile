# AGENTS.md — AI Agent 快速上手指南

> 本文件是给**无上下文的 AI Agent**（Claude Code / Cursor / Copilot 等）的首屏指令。
> 开始改代码前：**先读 [docs/dev/README.md](docs/dev/README.md)（索引）→ [docs/dev/conventions.md](docs/dev/conventions.md)（约定与陷阱，最重要）→ [docs/dev/key-references.md](docs/dev/key-references.md)（关键文件/符号索引）**。

## 项目一句话

**KrKr2 Next** = [KiriKiri2（吉里吉里2）](https://zh.wikipedia.org/wiki/%E5%90%89%E9%87%8C%E5%90%89%E9%87%8C2) 视觉小说引擎的现代化运行环境，**面向移动端（iOS + Android）**，macOS 为 Apple 开发目标，Linux 仅作 CI 宿主验证。

- **架构**：C++ 引擎（TVP/TJS2）离屏渲染（ANGLE：iOS/macOS=Metal 后端、Android=Vulkan 后端）→ IOSurface / SurfaceTexture 零拷贝 → Flutter 纹理显示；Dart 优先 FFI，MethodChannel 兜底。
- **本项目主页**：<https://github.com/FiresonZ/KrKr2-Next-Mobile>（fork 自 KrKr2-Next 二次开发）
- **直接上游（fork 来源）**：<https://github.com/reAAAq/KrKr2-Next>
- **代码来源（重构基础）**：<https://github.com/2468785842/krkr2>
- **说明**：本项目有大批量代码由 AI Agent 协作编写，文档体系（`docs/dev/`）专为 AI/开发者设计，请保持其与代码同步。

## 仓库结构速览

```
apps/flutter_app/             Flutter 壳应用（ios / android / macos 平台目录）
bridge/engine_api/            C ABI 引擎桥接（engine_create/tick/destroy…）
bridge/flutter_engine_bridge/ Flutter 平台插件（IOSurface / SurfaceTexture + Dart FFI + Kotlin/Swift）
cpp/core/                     C++ 引擎核心（tjs2/base/environ/sound/visual/movie…）
cpp/plugins/                  TJS 插件（psb/psd/layerex/motionplayer/fstat/cubism…）
build.sh + build/*.sh         iOS / Android / macOS 一键构建
CMakeLists.txt + CMakePresets.json   MacOS / iOS / Android / Linux 预设
vcpkg.json + vcpkg/triplets/  arm64-ios / arm64-android 依赖与 triplet
docs/                         文档（GitHub Pages 落地页 + FAQ/插件清单/兼容列表）
docs/dev/                     开发文档（AI Agent 速查，先读这里）
.github/workflows/            iOS / Android 打包 + Linux 引擎核心验证
```

## 构建命令

```bash
./build.sh ios release     # iOS（需 macOS/Xcode，或走 CI）
./build.sh android debug   # Android APK（Windows/macOS/Linux 均可，需 ANDROID_NDK_HOME）
./build.sh macos debug     # macOS（开发）
cmake --preset "Linux Debug Config" && cmake --build --preset "Linux Debug Build"  # CI 宿主验证
```

## 硬性约定（改代码前必读，详见 conventions.md）

1. **平台守卫是惰性的，别删**：源文件里 `#if defined(__ANDROID__)`、`#ifdef _WIN32`、`#if defined(__linux__)` 等分支在 Apple 构建中永不编译，是潜在复用代码；强行剥离是高危重构（conventions §2）。
2. **`win32/` 目录是跨平台共享实现**（音频/线程/系统控制），不是 Windows 专属，绝不能删（conventions §1）。
3. **SIMD（Highway）公式必须以 [tvpgl.cpp](cpp/core/visual/tvpgl.cpp) 的 `*_c` 标量为准**；高危公式缺陷（SubBlend/ScreenBlend_o/AdditiveAlphaBlend/PS alpha）已于 2026-09 修复，**待逐像素比对验证**（conventions §9）。
4. **Live2D（cubism）按 SDK 是否存在于磁盘条件编译**（`cpp/plugins/CMakeLists.txt`）：`cubism/Framework` + `Core/lib` 被 gitignore，CI 上自动禁用 `krkrlive2d.cpp`；缺库是正常状态，不是 bug（conventions §4）。
5. **vcpkg.json 的 angle 分平台**：Apple 用 `metal` feature，Android/Linux 用 `vulkan` feature，不可混用。
6. **Android 引擎形态是自包含 `libengine_api.so`**（`-Wl,--whole-archive` 打包全部引擎目标，等价 iOS `-force_load`）；JNI 胶水在 `bridge/engine_api/src/engine_api_android_jni.cpp`。
7. **`*.md` 已从 .gitignore 移除**，新增 md 文档正常 `git add`；`build/`（构建脚本目录）已反忽略（`!/build/`）。
8. 改 vcpkg 依赖后 CI 的 vcpkg 缓存 key 会变，首次会全量重编（半小时级），属正常。

## 当前状态（2026-09）

| 平台/模块 | 状态 |
|---|---|
| iOS 构建 + CI 打包 | ✅ 可出包（Live2D 条件编译修复后） |
| Android 恢复（triplet/preset/JNI/Kotlin 插件/壳层） | ✅ 代码就绪，**尚未真机验证** |
| Linux 引擎核心验证 CI（engine_verify.yml） | ⚠️ 已配置，**首次运行待绿灯**（Linux 从未实际编译过核心） |
| SIMD 公式缺陷修复 | ✅ 已修，**待 SIMD on/off 逐像素比对**（可在 Windows/Linux 上做） |
| 构建提速 | ✅ 已删 bullet3、catch2 移动端，CI 加 ccache |
| 测试基建 | ❌ 尚无 C++ 测试（tests/ 不存在），Linux CI 已预留 ctest 入口 |

## 建议的下一步

1. 跑通 Linux engine_verify CI（修首次编译问题）→ 2. 写 SIMD 比对测试挂 Linux CI → 3. Android 真机验证（用户有安卓手机）→ 4. iOS 产物在 iPhone 6s 验证 → 5. 真机问题修复后进入游戏兼容性测试（docs/dev/compatibility.md）。
