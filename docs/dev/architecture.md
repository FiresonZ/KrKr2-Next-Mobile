# 架构

## 总览

```
┌───────────────────────── apps/flutter_app (Dart/Flutter) ─────────────────────────┐
│  pages (home/game/settings/…)  ·  widgets/engine_surface.dart  ·  engine/bridge   │
└──────────────┬───────────────────────────────────────┬────────────────────────────┘
               │ Dart FFI (DynamicLibrary)             │ MethodChannel（兜底）
┌──────────────▼───────────────────┐   ┌───────────────▼─────────────────────────────┐
│ bridge/flutter_engine_bridge     │   │ iOS: FlutterEngineBridgePlugin.swift        │
│  lib/src/ffi/engine_ffi.dart     │   │  - EngineHostTexture (RGBA 上传, 兼容)       │
│  lib/src/ffi/engine_bindings.dart│   │  - EngineIOSurfaceTexture (零拷贝)           │
└──────────────┬───────────────────┘   └───────────────┬─────────────────────────────┘
               │ C ABI                                │ IOSurfaceID
┌──────────────▼───────────────────────────────────────▼─────────────────────────────┐
│ bridge/engine_api  (engine_api.cpp, C ABI)                                          │
│  engine_create / engine_tick / engine_open_game / engine_set_render_target_iosurface│
│  engine_read_frame_rgba / engine_send_input / engine_get_memory_stats …             │
└──────────────┬──────────────────────────────────────────────────────────────────────┘
               │ 链接 krkr2core + krkr2plugin
┌──────────────▼──────────────────────────────────────────────────────────────────────┐
│ cpp/core  (C++17 引擎)                                                               │
│  tjs2(脚本VM)  base(存储/归档/事件)  environ(平台/主循环)  visual(渲染/字体)          │
│  sound(音频)  movie(ffmpeg)  plugin(插件框架)  utils(线程/定时器)  extension          │
└──────────────┬──────────────────────────────────────────────────────────────────────┘
               │ ANGLE EGL/GLES2 离屏渲染 → IOSurface（零拷贝）
               ▼
          Flutter Texture 显示
```

## 渲染数据流（iOS/macOS）

1. 引擎通过 **ANGLE**（Metal 后端）创建 EGL Pbuffer Surface 做离屏渲染（GLES2）。
2. iOS/macOS 上，Swift 插件 `EngineIOSurfaceTexture.createSurface()` 创建
   **IOSurface 支撑的 CVPixelBuffer**，返回 `IOSurfaceID`。
3. Dart 调 `engine_set_render_target_iosurface(iosurfaceId, w, h)`，引擎直接渲染进该 IOSurface
   （绕过 `glReadPixels`，零拷贝）。
4. 每帧 `engine_tick` 后查 `engine_get_frame_rendered_flag`，新帧时调
   `notifyFrameAvailable(textureId)` 触发 Flutter 重绘。
5. 兼容路径：`engine_read_frame_rgba()` 读像素 → `EngineHostTexture` RGBA 上传。

> 引擎逻辑分辨率与设备像素：`engine_set_surface_size(w, h)` 设置。

## 桥接层设计

- **C ABI**（`bridge/engine_api/include/engine_api.h`）：稳定 ABI，`extern "C"`，版本 `ENGINE_API_VERSION`。

- **iOS**：`engine_api` 编译为**静态库** `libengine_api.a`，链接进 Runner；
  导出宏 `ENGINE_API_EXPORT_SYMBOLS` 保证符号在可执行文件内可见（`DynamicLibrary.process()` 可找到）。

- **macOS**：编译为**动态库** `libengine_api.dylib`，`ENGINE_API_BUILD_SHARED`，
  运行时由 Dart FFI 按路径加载。

- **Dart 侧**：优先 FFI；`FlutterEngineBridgePlatform`（plugin\_platform\_interface）提供
  MethodChannel 兜底实现 `MethodChannelFlutterEngineBridge`。

- **ANGLE 符号冲突**：Apple 上对 ANGLE 的 `libGLESv2/libEGL/libANGLE` 用
  `-force_load` 强制全量链接，避免与系统 OpenGL.framework 冲突（见 `bridge/engine_api/CMakeLists.txt`）。

## 引擎启动流程

1. Dart `engineCreate(writablePath, cachePath)`（`Application` 初始化、config manager 装载）。
2. `engineOpenGameAsync(gameRootPath, startupScript)` 后台线程打开游戏包（XP3 等）。
3. `engineGetStartupState` 轮询状态（IDLE→RUNNING→SUCCEEDED/FAILED），
   `engineDrainStartupLogs` 拉取启动日志。
4. `engineSetSurfaceSize` + `engineSetRenderTargetIOSurface` 建立渲染目标。
5. 主循环 `engineTick(deltaMs)`（Flutter vsync/Timer 驱动），输入经 `engineSendInput` 转发。

## 平台实现位置

| 能力                        | 实现                                             |
| ------------------------- | ---------------------------------------------- |
| iOS 平台层（路径/弹窗/内存/退出…）     | `cpp/core/environ/apple/ios/platform.mm`       |
| macOS 平台层                 | `cpp/core/environ/apple/macos/platform.mm`     |
| SDL/系统细节                  | `cpp/core/environ/sdl/tvpsdl.cpp`              |
| UI 桩（Flutter 接管 UI 后的空实现） | `cpp/core/environ/stubs/ui_stubs.cpp`          |
| 系统控制（事件分发/内存治理）           | `cpp/core/environ/win32/SystemControl.cpp`（共享） |
| 线程/定时器/剪贴板等               | `cpp/core/utils/win32/*`（共享）                   |
| 音频设备实现                    | `cpp/core/sound/win32/*`（共享）                   |

## GPU 合成管线现状（整理记录，勿大改）

> 本段为「现状整理 + 检查」记录。GPU 管线是方向性大改造，**暂不深入改动**，
> 待真机基准后再定方案（见 [perf-optimization.md](perf-optimization.md)）。

- **当前管线**：图层合成主要由 CPU 完成——`cpp/core/visual/` 的图层树在软件层用
  `tvpgl.cpp` / `simd/` 的混合函数把多层合成到中间缓冲；随后通过 ANGLE（EGL/GLES2）
  作为**最终绘制**（离屏到 IOSurface，零拷贝给 Flutter）。

- **因此**：混合计算（alpha/PS 混合等）目前主要吃 CPU/NEON，GPU 只负责"画上去"。

- **"全 GPU 合成"方向**：把图层混合搬进 GL shader，减少 CPU 像素搬运——收益不确定，
  需真机（帧率/功耗/发热）基准验证。

- **检查要点**：改渲染相关代码前先确认走的是哪个路径——
  `iosurface_attached`（零拷贝）还是 `engine_read_frame_rgba`（回读）；
  以及 SIMD 是否启用（见 conventions.md 第 9 节，已知公式缺陷会影响合成结果）。

