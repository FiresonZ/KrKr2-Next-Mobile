# 关键引用索引

> 改代码前先查这里。路径均相对仓库根。
> 模块编译边界以各 `CMakeLists.txt` 为准；源码用 `target_sources` 决定编哪些文件。

## 构建与配置

| 路径                               | 作用                                                     |
| -------------------------------- | ------------------------------------------------------ |
| `CMakeLists.txt`                 | 根编排：vcpkg 工具链、模块子目录、BUILD\_TOOLS/ENABLE\_TESTS（排除 iOS） |
| `CMakePresets.json`              | 仅 `MacOS Config` / `iOS Config`（含 Debug/Release）       |
| `build.sh`                       | 统一入口，支持 `ios` / `macos`                                |
| `build/build_ios.sh`             | iOS：CMake→静态库合并（libtool）→`flutter build ios`           |
| `build/build_macos.sh`           | macOS：CMake→dylib→打包进 App Frameworks→签名                |
| `vcpkg.json`                     | 依赖清单（manifest）                                         |
| `vcpkg-configuration.json`       | registry + overlay ports/triplets                      |
| `vcpkg/triplets/arm64-ios.cmake` | iOS triplet（arm64、deployment 15.0）                     |
| `.github/workflows/pages.yml`    | 部署 `docs/` 到 GitHub Pages                              |

## C ABI（engine\_api）

- `bridge/engine_api/include/engine_api.h` — 全部导出函数与结构体

- `bridge/engine_api/src/engine_api.cpp` — 实现（内部持有 `tTVPApplication`、主循环、渲染目标）

- `bridge/engine_api/include/engine_options.h` — 运行时选项键

主要函数：`engine_create` / `engine_destroy` / `engine_open_game(_async)` /
`engine_get_startup_state` / `engine_drain_startup_logs` / `engine_tick` /
`engine_pause` / `engine_resume` / `engine_set_option` / `engine_set_surface_size` /
`engine_get_frame_desc` / `engine_read_frame_rgba` / `engine_send_input` /
`engine_set_render_target_iosurface` / `engine_get_frame_rendered_flag` /
`engine_get_renderer_info` / `engine_get_memory_stats` / `engine_get_last_error` /
`engine_get_runtime_api_version`。

> 注意：`engine_set_render_target_surface`（Android）在 `engine_api.h` 中仍声明，但平台代码已删除，Apple 上返回 `NOT_SUPPORTED`。

## Dart / Flutter

| 路径                                                                           | 作用                                               |
| ---------------------------------------------------------------------------- | ------------------------------------------------ |
| `apps/flutter_app/lib/main.dart`                                             | 应用入口                                             |
| `apps/flutter_app/lib/engine/engine_bridge.dart`                             | 引擎生命周期封装                                         |
| `apps/flutter_app/lib/engine/flutter_engine_bridge_adapter.dart`             | 桥接插件适配                                           |
| `apps/flutter_app/lib/widgets/engine_surface.dart`                           | 纹理显示、零拷贝模式切换                                     |
| `apps/flutter_app/lib/pages/`                                                | home/game/settings/game\_detail/scrape\_select 页 |
| `apps/flutter_app/lib/services/`                                             | 游戏管理/封面/元数据/VNDB                                 |
| `apps/flutter_app/lib/l10n/`                                                 | zh/en/ja 本地化（`flutter gen-l10n`，见 `l10n.yaml`）   |
| `bridge/flutter_engine_bridge/lib/flutter_engine_bridge.dart`                | 插件公开 API（FFI 优先 + 平台兜底）                          |
| `bridge/flutter_engine_bridge/lib/src/ffi/engine_ffi.dart`                   | FFI 加载（iOS `DynamicLibrary.process()`）           |
| `bridge/flutter_engine_bridge/lib/src/ffi/engine_bindings.dart`              | C ABI 绑定                                         |
| `bridge/flutter_engine_bridge/ios/Classes/FlutterEngineBridgePlugin.swift`   | iOS 纹理（IOSurface + RGBA 兼容）                      |
| `bridge/flutter_engine_bridge/macos/Classes/FlutterEngineBridgePlugin.swift` | macOS 对应实现                                       |

## C++ 引擎（cpp/core）

| 路径                                            | 作用                                                                                    |
| --------------------------------------------- | ------------------------------------------------------------------------------------- |
| `cpp/core/CMakeLists.txt`                     | 模块聚合（tjs2/base/environ/extension/plugin/movie/sound/visual/utils）                     |
| `cpp/core/tjs2/`                              | TJS2 脚本 VM（bison 生成 parser，需系统 bison）                                                 |
| `cpp/core/base/`                              | 存储/归档（XP3/7z/zip/tar）/事件/消息                                                           |
| `cpp/core/environ/`                           | 平台抽象 + 主循环 + 应用生命周期                                                                   |
| `cpp/core/environ/apple/ios/platform.mm`      | **iOS 平台实现**（路径/弹窗/内存/退出）                                                             |
| `cpp/core/environ/apple/macos/platform.mm`    | macOS 平台实现                                                                            |
| `cpp/core/environ/Platform.h`                 | 平台函数声明（TVPGetMemoryInfo、TVP\_stat 等）                                                  |
| `cpp/core/environ/EngineLoop.cpp`             | 主循环、输入表                                                                               |
| `cpp/core/environ/MainScene.cpp`              | 场景/窗口协调                                                                               |
| `cpp/core/environ/ConfigManager/`             | 全局/个人/语言配置                                                                            |
| `cpp/core/environ/sdl/tvpsdl.cpp`             | SDL 系统细节（共享）                                                                          |
| `cpp/core/environ/stubs/ui_stubs.cpp`         | UI 桩（Flutter 接管 UI）                                                                   |
| `cpp/core/environ/win32/SystemControl.cpp/.h` | 系统控制（共享，勿删）                                                                           |
| `cpp/core/visual/`                            | 渲染（`RenderManager_ogl.cpp`、`ogl/krkr_egl_context.cpp`、`ogl/angle_backend.h`）、字体、图像编解码 |
| `cpp/core/sound/` + `sound/win32/`            | 音频（OpenAL 实现位于 win32 目录，共享）                                                           |
| `cpp/core/movie/ffmpeg/`                      | 视频播放器（AE/KRMovie）                                                                     |
| `cpp/core/utils/` + `utils/win32/`            | 线程/定时器/剪贴板（win32 目录为共享实现）                                                             |
| `cpp/core/plugin/`                            | 插件框架（ncbind）                                                                          |

## 插件（cpp/plugins）

| 路径                                              | 作用                                                                          |
| ----------------------------------------------- | --------------------------------------------------------------------------- |
| `cpp/plugins/CMakeLists.txt`                    | 插件聚合（psbfile/psdfile/layerex\_draw/motionplayer/kagparserex/fstat + cubism） |
| `cpp/plugins/psbfile/`                          | PSB 图像/动画格式                                                                 |
| `cpp/plugins/psdfile/`                          | PSD 解析                                                                      |
| `cpp/plugins/layerex_draw/`                     | 扩展绘制（`general/`，非 Windows 分支）                                               |
| `cpp/plugins/motionplayer/`                     | 动态立绘播放                                                                      |
| `cpp/plugins/kagparserex/`                      | KAG 脚本扩展                                                                    |
| `cpp/plugins/fstat/`                            | 文件状态                                                                        |
| `cpp/plugins/cubism/`                           | Live2D（SDK gitignored，需手动放置 `Core/lib/` 与 `Framework/`）                     |
| `cpp/plugins/krkrgles.cpp` 等 | 顶层插件源（全部参与编译，已含平台守卫） |
| `cpp/plugins/krkrlive2d.cpp` | Live2D 插件，**仅当 Cubism SDK 存在时编译**（见 conventions §4） |

## 其他

| 路径                                 | 作用                                          |
| ---------------------------------- | ------------------------------------------- |
| `platforms/apple/macos/`           | macOS 独立资源（Info.plist/Icon，入口已由 Flutter 接管） |
| `tools/xp3/`                       | XP3 归档命令行工具（macOS/Linux 构建）                 |
| `cmake/scripts/sync_folder.py`     | 资源同步脚本（当前无构建引用）                           |
| `docs/`（含 `docs/dev/`）           | GitHub Pages 落地页 + 开发文档（合并自旧 `doc/`）        |

