# 技术栈

## 语言与构建

| 项               | 选择                  | 说明                                                              |
| --------------- | ------------------- | --------------------------------------------------------------- |
| C++             | C++17（`-std=c++17`） | 引擎核心，`CMAKE_POSITION_INDEPENDENT_CODE ON`                       |
| Objective-C/C++ | 仅在 Apple 平台启用       | `environ/apple/{ios,macos}/platform.mm`                         |
| Dart / Flutter  | SDK `^3.11.0`       | 壳应用 + 插件，`flutter >=3.3.0`                                      |
| CMake           | ≥3.28               | 根 + 各子模块 CMakeLists，预设见 `CMakePresets.json`                     |
| Ninja           | 构建生成器               | 预设中指定                                                           |
| vcpkg           | 依赖管理                | manifest 模式，`vcpkg-configuration.json` 挂 overlay ports/triplets |
| ccache          | 可选                  | 根 CMakeLists 自动探测                                               |

## 平台目标（Mobile-first）

- **iOS**：主目标，部署目标 `15.0`，架构 `arm64`，triplet `arm64-ios`，引擎为静态库。
- **Android**：主目标，API 24，架构 `arm64-v8a`，triplet `arm64-android`，引擎为自包含 `libengine_api.so`。
- **macOS**：Apple 开发/调试目标，Flutter 壳，`libengine_api.dylib` 打进 Frameworks。
- **Linux**：仅 CI 宿主验证目标（`engine_verify.yml`），不产出 App。

> 平台收敛与恢复历史见 `conventions.md` §7（先收敛为 iOS+macOS，后恢复 Android 定位移动端）。

## 引擎核心依赖（vcpkg.json）

| 库                                                  | 用途                                                 |
| -------------------------------------------------- | -------------------------------------------------- |
| ANGLE（`metal` / `vulkan` feature）                | EGL/GLES2 渲染：Apple 用 Metal 后端，Android/Linux 用 Vulkan 后端（`KRKR_USE_ANGLE=1`） |
| FFmpeg                                             | 视频/音频解码（`cpp/core/movie/ffmpeg`）                   |
| OpenAL-soft                                        | 音频输出                                               |
| Vorbis / OpusFile                                  | 音频解码                                               |
| libarchive / 7zip / minizip / zstd / lz4           | 归档（XP3 等）解压                                        |
| libjpeg-turbo / libpng / libwebp / jxrlib / libbpg | 图像解码                                               |
| FreeType                                           | 字体光栅化                                              |
| OpenCV（imgproc/core）                               | 图像处理                                               |
| boost（locale/spirit/phoenix/iostreams）             | 引擎工具                                               |
| libgdiplus                                         | GDI+ 兼容层（`layerex_draw` 等插件用）                      |
| SDL2                                               | `environ/sdl/tvpsdl.cpp` 用                         |
| spdlog / fmt                                       | 日志                                                 |
| oniguruma                                          | 正则                                                 |
| tinyxml2 / libxml2 / uchardet                      | XML/编码                                             |
| unrar                                              | RAR 解压                                             |
| highway                                            | SIMD 像素混合（`visual/simd/tvpgl_simd_*`）              |
| bullet3                                            | 物理（部分插件）                                           |
| cubism（Live2D，非 vcpkg）                             | `cpp/plugins/cubism`，SDK 需手动下载（gitignored）         |

> 平台条件：`argparse` 仅 macOS（工具用）；`catch2`/`openmp` 排除 iOS；其余全平台共享。

## Flutter 壳应用依赖（apps/flutter\_app/pubspec.yaml）

- `flutter_engine_bridge`（本地 path 依赖，FFI + MethodChannel）

- `shared_preferences`、`path_provider`、`file_picker`、`image_picker`

- `flutter_svg`、`url_launcher`、`http`、`intl`/`flutter_localizations`（l10n：zh/en/ja）

- 资源：`assets/icons/`（opengl/opengles/vulkan svg）

