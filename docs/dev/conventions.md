# 约定与历史陷阱（务必阅读）

> 这些是前人在平台收敛过程中踩过的坑与重要决策。**改代码前先读本页**，
> 尤其是涉及目录删除、平台守卫、vcpkg 时。

## 1. 名为 `win32` 的目录是「跨平台共享实现」，不是 Windows 专属 ⚠️

以下目录被 **所有 Apple 平台无条件编译**，是共享实现，**绝不能删**：

| 目录 | 内容 |
|------|------|
| `cpp/core/sound/win32/` | 音频设备实现（CDDA/MIDI/Wave/WaveMixer/tvpsnd），基于 OpenAL |
| `cpp/core/utils/win32/` | 线程/定时器/剪贴板/触控板等实现 |
| `cpp/core/environ/win32/SystemControl.cpp` | 系统控制（事件分发、内存治理），根 `environ/CMakeLists.txt` 无条件编译 |

`environ/win32/` 目前仅保留 6 个必需文件：
`SystemControl.cpp/.h`、`TVPWindow.h`、`ApplicationSpecialPath.h`、`EmergencyExit.h`、`DetectCPU.h`。
其余 Windows UI 死代码（TVPWindow.cpp、WindowFormUnit、MouseCursor、TouchPoint 等）已删除。

## 2. 平台守卫是惰性的，删除需谨慎

共享源文件中存在 `#if defined(__ANDROID__)`、`#if defined(__linux__)`、`#ifdef WIN32` 等分支。
在 Apple 构建中这些分支**永远不会编译**（惰性死代码），不影响构建。
**默认不要动它们**——强行剥离是高风险重构，收益低。例子：
`engine_api.cpp`、`ScriptMgnIntf.cpp`、`StorageImpl.cpp`、`krkr_egl_context.cpp`、
`RenderManager_ogl.cpp`、`WaveMixer.cpp`、`ui_stubs.cpp`、`krkrgles.cpp` 等。
若确实需要清理，必须逐文件确认 Apple 路径仍完整。

## 3. vcpkg/ports 是共享的第三方构建配方，不要删

`vcpkg/ports/*` 中 7zip/ffmpeg/angle 等的平台补丁（如 `0001-android-ffmpeg.patch`、
`PlatformAndroid.cmake`）虽然名义上属于其他平台，但**在现有配置中是无条件/按端口逻辑应用**的，
且 vcpkg 只会在 Apple triplet 下被调用。删除可能破坏现有可用构建。
平台目标由 `vcpkg.json` + `vcpkg/triplets/arm64-ios.cmake` 控制（已收敛）。

## 4. Live2D Cubism SDK 需手动放置（可选，缺库自动禁用）

`cpp/plugins/cubism/` 仅含头文件；`Core/lib/`（预编译静态库）与 `Framework/`
被 `.gitignore` 忽略，需从 live2d.com 下载后按路径放置：
- iOS：`Core/lib/ios/Release-iphoneos/libLive2DCubismCore.a`
- macOS：`Core/lib/macos/{arm64,x86_64}/libLive2DCubismCore.a`
- Android：需要 Android 版 core 库，路径需自行补充到 `cpp/plugins/CMakeLists.txt`

缺库时 **不会导致构建失败**：`plugins/CMakeLists.txt` 检测 SDK 是否存在，
不存在则跳过 `krkrlive2d.cpp`、把 `CubismFramework` 建成空的 INTERFACE 目标
（2026-09 修复：此前 CI 因缺 Framework 直接 CMake 报错）。

## 5. iOS / macOS 引擎二进制形态不同

- **iOS**：`engine_api` 为**静态库**，定义 `ENGINE_API_EXPORT_SYMBOLS`，链接进 Runner；
  Dart 用 `DynamicLibrary.process()` 定位符号。静态库合并脚本见 `build_ios.sh`。
- **macOS**：`engine_api` 为**动态库** `libengine_api.dylib`，定义 `ENGINE_API_BUILD_SHARED`，
  打包进 App 的 `Contents/Frameworks/`。
- `bridge/flutter_engine_bridge/ios/Libs/*.a` 是构建产物（gitignore），勿提交。

## 6. ANGLE 与系统 OpenGL.framework 符号冲突

Apple 上必须对 ANGLE 的 `libGLESv2`/`libEGL`/`libANGLE` 用 `-force_load` 强制全量链接
（见 `bridge/engine_api/CMakeLists.txt`），否则 GL/EGL 符号可能被系统框架抢先解析。

## 7. 平台收敛与恢复历史（2026-09）

仓库先收敛为 **iOS + macOS**，随后（2026-09）恢复 Android，定位改为 **mobile（iOS + Android）**。

第一次收敛（iOS + macOS）时删除：

| 已删除 | 说明 |
|--------|------|
| `apps/flutter_app/{android,linux,windows}/` | Flutter 壳平台目录 |
| `bridge/flutter_engine_bridge/{android,linux,windows}/` 及 example 中对应目录 | 插件平台实现 |
| `platforms/{android,linux,windows}/` | 平台入口（Android JNI、Linux、Windows） |
| `cpp/core/environ/{android,linux}/` | JNI/Linux 平台实现 |
| `build/build_android.sh`、`cmake/vcpkg_android.cmake` | Android 构建 |
| `vcpkg/triplets/*-android.cmake`（4个） | Android triplets |
| `cpp/plugins/layerex_draw/windows/` | Windows 专属绘制 |
| `environ/win32/` 大部分死代码 | 见第 1 节 |

> 保留项：`platforms/apple/macos/`（macOS 资源）、`tools/`（macOS 工具）、
> `docs/dev/`（本文档）、`docs/`（GitHub Pages 落地页）。

第二次恢复（Android，2026-09）新增：

| 新增 | 说明 |
|------|------|
| `apps/flutter_app/android/` | Flutter Android 壳层（标准模板，gradlew/wrapper jar 由 `flutter create` 再生成） |
| `bridge/flutter_engine_bridge/android/` | Kotlin 插件（MethodChannel + SurfaceTexture + JNI） |
| `bridge/engine_api/src/engine_api_android_jni.cpp` | JNI 胶水（`krkr_GetNativeWindow` 定义、`nativeSetSurface`/`nativeDetachSurface`） |
| `vcpkg/triplets/arm64-android.cmake` | Android triplet（arm64-v8a，API 24） |
| `build/build_android.sh` | Android 一键构建（镜像 build_ios.sh） |
| `.github/workflows/android_package.yml` | Android CI 打包（Ubuntu runner） |

## 8. 其他约定

- Dart 壳应用中存在大量 `Platform.isAndroid` 等运行时分支，在 iOS/macOS 上恒为 false，
  编译运行无影响；**属业务逻辑**，与平台基础设施无关，未清理。这些分支正是 Android 恢复时
  的现成支持（SurfaceTexture 零拷贝 + RGBA 回读兜底）。
- `ENABLE_TESTS` / `BUILD_TOOLS` 在 iOS/Android 上默认关闭（`CMakePresets.json` 对应预设里 `false`）；
  Linux 宿主验证预设里打开。
- 根 `CMakeLists.txt` 不再生成独立可执行 `krkr2`（Flutter 壳接管入口），仅构建引擎库。
- `docs/`（GitHub Pages + FAQ/插件清单/兼容列表）与 `docs/dev/`（开发文档）已合并为单一 docs 目录；
  `doc/` 旧目录与无引用图片已删除（2026-09）。

## 9. SIMD（Highway）审计记录（2026-09）

> 结论：**无语法错误**（Highway foreach_target 模式、HWY_EXPORT/HWY_DYNAMIC_DISPATCH 结构正确），
> 但存在**多处向量公式与标量参考不一致**的缺陷。修复时务必逐函数对照
> `cpp/core/visual/tvpgl.cpp` 中 `*_c` 标量实现。

### 高危（输出明显错误）

1. **SubBlend 系（`tvpgl_simd_arithmetic_blend.cpp` 全部 4 个）**
   SIMD 用 `SaturatedSub(d, s)`（= max(d−s,0)）；标量 `TVPSubBlend_c` 语义是
   **`max(s+d−255, 0)`**（饱和 d+s−255）。向量路径整段错误，且与同函数尾部标量不一致 → 行内带状错误。

2. **ScreenBlend_o / ScreenBlend_HDA_o（`tvpgl_simd_arithmetic_blend.cpp`）**
   标量（`TVPScreenBlend_o_c`）：`(~d) * ~((s*opa)>>8) >> 8`（无外层取反）；
   SIMD：`~((~d) * ((~s*opa)>>8) >> 8)`。源缩放公式与最终取反均不同，数值差异巨大。

### 中危（alpha 通道不一致，合成边缘出错）

3. **AdditiveAlphaBlend / AdditiveAlphaBlend_o（`tvpgl_simd_premul_blend.cpp`）**
   标量不对 alpha 字节缩放（结果 alpha = src_a）；SIMD 对 alpha 字节也做
   `d_a*(255-s_a)>>8` 缩放再饱和加 → 向量与尾部不一致。

4. **Ps*Blend NORM / _o 全系（`tvpgl_simd_ps_blend.cpp` / `_ps_blend2.cpp`，8 模式 × 2）**
   标量（`tvpps.inc` + `TVPPS_ALPHABLEND`）NORM/_o 输出 **alpha=0**（只写 RGB）；
   SIMD 的 `PsApplyAlpha` 对 alpha 字节做 `(s_a*a>>8)+(d_a*(255-a)>>8)` 混合 → 不一致。

### 低危（位级偏差 / 死代码）

5. **AlphaBlend / ConstAlphaBlend / PS alpha 应用**：`(s*a>>8)+(d*(255-a)>>8)` 与标量
   `d+((s-d)*a>>8)` 舍入至多差 1，视觉可忽略，但与 C 参考非位一致（对截图比对/Z 兼容测试有影响）。
6. **ConvertAlphaToAdditiveAlpha**：SIMD `(ch*a)>>8`（÷256）vs 标量 `(ch*a)/255`；
   255 满 alpha 时 SIMD 得 254 而非 255。
7. **`tvpgl_simd_common.h` 的辅助函数（BlendChannelU16 等）**：`(s-d)*a` 存在 u16 溢出隐患，
   且**全部未被任何实现文件使用**（死代码）。未来复用前必须重写。
8. **未注册的导出函数**：`ConstAlphaBlend_d/a`、`AdditiveAlphaBlend_a/ao`、`DoBoxBlurAvg*`、
   `ChBlur*` 等声明与实现存在但 `tvpgl_simd_init.cpp` 未注册——死代码，无害但易误导。

### 修复建议

- 逐函数将 SIMD 公式**对齐标量参考**（SubBlend → `max(d+s-255,0)`；ScreenBlend_o →
  标量式；AdditiveAlphaBlend 的 alpha=s_a；PS NORM 的 alpha=0 等）。
- 修复后做 **SIMD on/off 输出比对**（`TVPGL_SIMD_Init` 是否调用）确认逐像素一致。
  该验证**不需要 macOS**：在 Windows（SSE/AVX2）或 Android（NEON）上编译同一份核心即可，
  公式缺陷与指令集无关。
- 若短期不修：可在 `tvpgl_simd_init.cpp` 中把高危函数改为不注册（回退标量），避免错误渲染。

## 10. Android 恢复要点（2026-09）

- **引擎侧早已就绪**：`engine_api.cpp` 的 Android 渲染路径（`InitializeWithWindow`/
  `AttachNativeWindow`/自动挂载 ANativeWindow）与 `__ANDROID__` ifdef 是恢复前就存在的，
  只缺 `krkr_GetNativeWindow()`/`krkr_GetSurfaceDimensions()` 的实现（现在在
  `engine_api_android_jni.cpp`，由 `-landroid -llog` 链接）。
- **`.so` 必须自包含**：Android 无法像 iOS 那样额外合并静态库，`engine_api` 以 SHARED 形态
  `-Wl,--whole-archive` 打进 krkr2core/krkr2plugin 全部目标（等价 iOS `-force_load`）。
- **vcpkg angle 分平台**：`vcpkg.json` 中 angle 拆成两条 —— Apple 用 `metal` feature，
  Android 用 `vulkan` feature（feature 带 `supports` 约束，混用会编译失败）。
- **libpng** 平台条件扩展为 `osx | ios | android`（`find_package(PNG REQUIRED)` 在
  visual/CMakeLists.txt，所有平台都需要）。
- **Android 壳层的 gradlew/wrapper jar 是二进制产物**，已被 `.gitignore` 忽略；
  若缺失，在 `apps/flutter_app` 下执行 `flutter create --platforms=android .` 一键再生成
  （不会破坏 Dart 代码）。Gradle/AGP/Kotlin 版本需与本机 Flutter 匹配，`flutter create` 会
  生成匹配版本，优先采用。
- **minSdk 24**：`apps/flutter_app/android/app/build.gradle` 与 vcpkg triplet 一致
  （API 24 = Android 7.0），低于此版本的设备无法加载引擎 .so。
