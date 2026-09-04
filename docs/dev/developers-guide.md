# 开发者入门指南（面向人类开发者）

> 如果你会基础 C++、打过 OI/ACM，这份指南带你 30 分钟进入状态。
> 目标：知道项目是什么、代码在哪、一条渲染请求怎么走、怎么改怎么调试。
> 更精确的索引见 [key-references.md](key-references.md)，历史陷阱见 [conventions.md](conventions.md)。

## 1. 项目是什么

一个 **KiriKiri2（吉里吉里2）视觉小说引擎**的现代化移植：原版引擎是 C++ 写的、跑 Windows；
这里把引擎核心保留为 C++，外面套了一个 **Flutter（Dart）** 壳来做 UI，运行在 iOS / macOS。

- **引擎**（C++）：负责运行游戏脚本（TJS2）、解码图片/音频/视频、图层合成，输出一帧一帧的像素。

- **壳**（Flutter）：负责窗口、按钮、文件选择、游戏库管理，把引擎输出的帧显示到屏幕上。

- **桥**（C ABI + FFI）：引擎和壳之间的"管道"。

## 2. 三个关键概念

1. **BGRA8888 像素**：引擎内部图片是 32 位 BGRA（低字节到高字节 = 蓝、绿、红、alpha）。
   `tjs_uint32` 一个像素。alpha=0 透明、255 不透明。几乎所有混合函数都是对 `tjs_uint32*` 数组按像素操作。
2. **离屏渲染 + 零拷贝**：引擎不用真窗口，而是用 ANGLE（OpenGL ES 2.0 的实现，底层是 Metal）在
   一块内存/纹理上画，画完通过 **IOSurface** 直接给 Flutter 显示，不拷像素。慢速兜底是
   `engine_read_frame_rgba`（glReadPixels 回读）。
3. **TJS2 脚本**：吉里吉里的游戏脚本语言（类似 JS）。引擎的 `cpp/core/tjs2/` 是它的解释器（用 bison 生成 parser）。

## 3. 目录地图（哪里是什么）

```
apps/flutter_app/        Flutter 壳（Dart）。lib/pages 页面、lib/engine 引擎封装
bridge/engine_api/       桥核心：C ABI。include/engine_api.h 是接口清单，src/engine_api.cpp 是实现
bridge/flutter_engine_bridge/  Flutter 插件：Dart FFI + iOS/macOS Swift 纹理
cpp/core/                引擎核心（最重要的目录）
  tjs2/       脚本解释器
  base/       存储/归档/事件/消息（XP3、7z、zip 解包在这）
  environ/    平台抽象 + 主循环（iOS/macOS 平台代码在 environ/apple/）
  visual/     渲染：图层合成、图像编解码、字体、SIMD 像素混合（simd/）
  sound/      音频（OpenAL）
  movie/      视频（FFmpeg）
  plugin/     插件框架（ncbind：把 C++ 类暴露给 TJS 脚本）
cpp/plugins/  TJS 插件：PSB/PSD 解析、Live2D、扩展绘制等
build.sh      一键构建（ios/macos）
```

## 4. 一条渲染请求怎么走（核心路径）

```
游戏脚本(TJS) 调用图层操作
  → cpp/core/visual/ 图层树合成（LayerManager）
  → 每帧 Application->Run() + TVPDrawSceneOnce()
  → ANGLE 渲染到 IOSurface（EGLContextManager::AttachIOSurface）
  → Flutter 侧收到"新帧"通知 → Texture 显示
```

桥的调用链（Dart→C++）：

```
Dart:  FlutterEngineBridge.engineTick(deltaMs)
  → FFI: engine_tick(handle, deltaMs)          (engine_api.cpp)
  → C++: 引擎主循环（Application->Run()）
  → Dart: engineGetFrameRenderedFlag() → notifyFrameAvailable(textureId)
```

## 5. 改代码的常见入口

| 想做什么                 | 去哪改                                                                    |
| -------------------- | ---------------------------------------------------------------------- |
| 修一个混合/滤镜效果           | `cpp/core/visual/simd/`（SIMD）或 `tvpgl.cpp`（标量参考）                       |
| 修脚本引擎行为              | `cpp/core/tjs2/`                                                       |
| 加一个新的 TJS 可调用的类/函数   | `cpp/core/plugin/`（ncbind）或 `cpp/plugins/`                             |
| 改 iOS 平台行为（弹窗/路径/内存） | `cpp/core/environ/apple/ios/platform.mm`                               |
| 改 Flutter UI         | `apps/flutter_app/lib/pages/`                                          |
| 加桥接 API              | `engine_api.h` + `engine_api.cpp` + `lib/src/ffi/engine_bindings.dart` |

## 6. 调试三板斧

1. **日志**：C++ 用 `spdlog`（`spdlog::info/warn/error`），iOS 上能看到控制台输出；
   Dart 用 `debugPrint`。引擎启动日志可通过 `engineDrainStartupLogs` 拉取。
2. **开关**：`tvpgl_simd_init.cpp` 里 `TVPGL_SIMD_Init()` 决定是否启用 SIMD 混合——
   想对比"标量 vs SIMD"就把它的注册行注释掉，看画面是否变化。
3. **真机**：`./build.sh ios debug` 后用 Xcode 打开 `apps/flutter_app/ios/Runner.xcworkspace` 跑真机，
   断点、日志都在。

## 7. 常用命令

```bash
./build.sh ios release      # 构建 iOS（release）
./build.sh ios debug        # 构建 iOS（debug）
./build.sh macos debug      # 构建 macOS（开发，最快）
JOBS=16 ./build.sh ios release   # 多核加速
```

## 8. 进阶路线

1. 先读 [architecture.md](architecture.md) 的架构图 + 渲染数据流。
2. 再读 [key-references.md](key-references.md)，把关键文件位置记熟。
3. 然后读 [conventions.md](conventions.md)（尤其是 SIMD 审计记录，那里有已知缺陷）。
4. 从一个小 bug 入手练手（比如 SIMD 审计里 SubBlend 的公式错误）。

