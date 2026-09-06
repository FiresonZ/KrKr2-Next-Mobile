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
6. **Android 引擎形态是自包含 `libengine_api.so`**：插件子库（`krkr2plugin`/`psbfile`/`motionplayer`…）用 `target_sources(PUBLIC)`，其源码经 `INTERFACE_SOURCES` **直接编进 `engine_api.so`**，引擎以**普通链接** `krkr2core + krkr2plugin` 打包（对齐上游 reAAAq/KrKr2-Next）；**不要再加 `--whole-archive`**，否则会把 psbfile/motionplayer 的对象再拉一份，触发 ld.lld 重复符号；JNI 胶水在 `bridge/engine_api/src/engine_api_android_jni.cpp`。
7. **`*.md` 已从 .gitignore 移除**，新增 md 文档正常 `git add`；`build/`（构建脚本目录）已反忽略（`!/build/`）。
8. 改 vcpkg 依赖后 CI 的 vcpkg 缓存 key 会变，首次会全量重编（半小时级），属正常。
9. **待办在 [docs/dev/todo.md](docs/dev/todo.md)**，动手前先看是否已有相关条目与黑屏探针结论。

## 当前状态（2026-09）

| 平台/模块 | 状态 |
|---|---|
| iOS 构建 + CI 打包 | ✅ 可出**无签名 IPA**（工作流直接装 `Payload/Runner.app` 打 nosign.ipa，供 AltStore/Sideloadly 侧载测试）；**已出测试版骨架，准备预发布** |
| iOS 黑屏诊断 | 🔬 探针已加：`ui_stubs.cpp::UpdateDrawBuffer` 上报 `SourceSample/PostBlit/draw/BlackScreen`；真机日志已**排除视频**（`VideoOverlay total=0`），根因转向 **Z(krkrz) 插件兼容**（缺 drawdeviceD3DZ/kztouch/k2compat 等，主 DrawBuffer 从未被合成，源纹理保持初始黑），详见 [docs/dev/todo.md](docs/dev/todo.md) |
| Android 构建链路（triplet/preset/JNI/Kotlin 插件/壳层/平台层） | 🛠 引擎 C++ 已编译链接出 `libengine_api.so`（triplet arm64 ABI 修复 + 去 whole-archive + oboe + 补 Android 平台层）；现进入 Flutter/Gradle 打包阶段，卡 Gradle 版本下限（wrapper 升 8.14.3）。持续推进中 |
| vcpkg meson × Android | ⚠️ 已知坑：`get_cmake_vars` 无论 triplet 的 `ANDROID_ABI=arm64-v8a` 都回落 `--target=armv7-none-linux-androideabi21`；cmake/autotools 端口现靠全局 `-DANDROID_ABI` 已正常，仅 meson 端口（如 glib）会与 arm64 库错配。修法见 `vcpkg/ports/glib/portfile.cmake` |
| Linux 引擎核心验证 CI（engine_verify.yml） | ✅ 首次绿灯（新增 Linux 宿主平台实现 platform_linux.cpp 等 11 项修复） |
| SIMD 公式缺陷修复 | ⚠️ 已回退保正确，修复列为待办：tests/tvpgl_simd_compare 逐像素比对证实 23 处 SIMD≠标量；PS 全系混合 / SubBlend_o / ScreenBlend 现指回 `*_c` 标量（`tvpgl_simd_init.cpp` 已注释对应注册），待逐模式修到与标量位级一致后放回 |
| 构建提速 | ✅ 已删 bullet3、catch2 移动端，CI 加 ccache |
| 测试基建 | ✅ 已建 SIMD 比对测试 tests/tvpgl_simd_compare（**生产标量**＝TVPGL_C_Init 派发 vs SIMD 派发，挂 ctest）；已证实并定位 23 处 SIMD≠标量，现回退后全绿 |

## 建议的下一步

1. ~~跑通 Linux engine_verify CI（修首次编译问题）~~ ✅ 已绿灯
2. ~~写 SIMD 比对测试挂 Linux CI~~ ✅ tests/tvpgl_simd_compare（已开跑，证实并定位 23 处 SIMD≠标量）
3. ~~PS 全系 / SubBlend_o / ScreenBlend 先回退标量保正确~~ ✅（`tvpgl_simd_init.cpp`，修 SIMD 列待办）
4. 重跑 Linux engine_verify CI，确认 ctest 全绿（回退后）
5. 读 iOS 真机日志，按 `BlackScreen` 探针结论决定是否先做 krmovie Present（详见 [docs/dev/todo.md](docs/dev/todo.md)）
6. 构 Android APK + iOS nosign IPA 真机实测（iOS 侧载；Android 待 glib arm64 meson 修复的 CI 验证）
7. 逐模式修 SIMD 至位级一致（待办：PsApplyAlpha 舍入序 + SubBlend_o/ScreenBlend alpha + Overlay/HardLight 分支），tests 逐模式验证后放回
8. 真机问题修复后进入游戏兼容性测试（docs/dev/compatibility.md）
