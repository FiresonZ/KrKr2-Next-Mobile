# KrKr2 Next — 版主小白开发指引（用途 / 内置功能 / 上手指南）

> 本文面向**刚接触本项目的开发者**（尤其是"小白"）：把每个目录/文件是干什么的、
> 引擎内置了哪些功能、怎么把它跑起来、怎么往里面加游戏、怎么做简单排错，一一讲清楚。
> 想了解更深入的技术细节，请继续读：
> [developers-guide.md](developers-guide.md)（人类开发入门）、[architecture.md](architecture.md)（架构）、
> [build.md](build.md)（构建）、[key-references.md](key-references.md)（关键文件索引）。

---

## 一、这个项目到底是什么？

一句话：**KrKr2 Next = 一个能在手机（iOS/Android）上运行"吉里吉里2"游戏引擎的现代运行环境。**

吉里吉里2（KiriKiri2 / TVP）是日式视觉小说（Galgame）最常用的引擎，很多老游戏
（魔女的夜宴、Clover Days 等）就是用它写的。本项目的目标：
- 让这些 PC 游戏能直接搬到手机上玩；
- 用 Flutter 做外壳（界面、文件选择、纹理显示）；
- 用 C++ 引擎（TJS2 + 渲染）做核心，保持与原版脚本 100% 兼容。

```
你选一个游戏目录/XP3 → Flutter 壳 → C++ 引擎解析脚本并渲染 → 通过纹理共享显示到屏幕
```

---

## 二、仓库目录都是干嘛的？（小白地图）

```
/workspace
├── apps/flutter_app/              ← 🎨 Flutter 外壳应用（你打开 App 看到的界面都在这里）
│   ├── ios/ android/ macos/      ←   各平台工程（Info.plist、build.gradle、签名配置）
│   └── lib/                      ←   Dart 代码（Home 选游戏、Settings、游戏页、l10n 文案）
├── bridge/engine_api/            ← 🔌 C ABI 桥（引擎的门面：engine_create / tick / destroy）
├── bridge/flutter_engine_bridge/ ← 🔌 Flutter 平台插件（iOS IOSurface / Android SurfaceTexture
│                                    + Dart FFI，负责把引擎渲染的帧"零拷贝"送上屏幕）
├── cpp/core/                     ← ⚙️ C++ 引擎核心（最重要的部分）
│   ├── tjs2/                     ←   TJS2 脚本引擎（游戏里 .tjs/.ks 就是它来解释执行）
│   ├── base/                     ←   基础：存储、XP3 解包、KAG 标签解析、系统接口、消息
│   ├── visual/                   ←   渲染：图层、图像解码、drawdevice、OpenGL 合成
│   ├── environ/                  ←   平台层：iOS/macOS/Android/Linux/Windows 适配、UI stub
│   ├── sound/                    ←   声音：波形、BGM、解码（vorbis/opus 等）
│   ├── movie/ffmpeg/             ←   🎬 krmovie 视频播放（基于 ffmpeg）
│   └── plugin/                   ←   插件系统（ncbAutoRegister / ncbind）
├── cpp/plugins/                  ← 🧩 内置 TJS 插件（psb/psd/layerex/motionplayer/fstat/cubism…）
├── build.sh + build/*.sh         ← 🛠 一键构建脚本（iOS / Android / macOS）
├── CMakeLists.txt + CMakePresets.json  ← 各平台构建预设（Windows/MinGW 等也在这）
├── vcpkg.json + vcpkg/           ← 📦 三方依赖管理（vcpkg manifest + 自订 triplet/overlay 端口）
├── docs/                         ← 📚 对外文档（GitHub Pages 落地页 + FAQ/插件清单）
│   └── dev/                      ←   开发文档（给开发者/AI Agent 看的，含本文件）
└── .github/workflows/            ← 🤖 CI（iOS 打 IPA、Android 打 APK、Linux 引擎验证）
```

### 你要改"界面" → 去 `apps/flutter_app/lib/`
App 长什么样、按钮文案（比如之前的"打包为 XP3"）、导入游戏流程，都在这里。纯 Dart。

### 你要改"引擎逻辑/兼容性" → 去 `cpp/core/`
解析脚本对不对、渲染对不对、xp3 能不能打开，都在这里。纯 C++。

### 你要处理"依赖装不上" → 去 `vcpkg.json` + `vcpkg/triplets/` + `vcpkg/ports/`
Android 交叉编译那些坑（boost 32 位、glib meson）就是在这里解决的。

---

## 三、引擎内置了哪些功能？（装了什么"料"）

### 3.1 脚本与存档
- **TJS2 脚本引擎**（`cpp/core/tjs2`）：解释 KiriKiri 的游戏脚本，含类、闭包、正则等完整特性。
- **KAG 标签解析器**（`cpp/core/base`，`KAGParser`）：把 `.ks` 里的 `[tag]` 转成引擎动作。
- **XP3 资源解包**：游戏资源包 `.xp3`；支持目录散装 + 同目录多个 xp3 自动挂载
  （`TVPAutoMountProjectXP3Archives`）。

### 3.2 渲染
- **图层（Layer）系统**：视觉小说的背景/立绘/对话框/文字都是一层层叠上去的。
- **图像解码**：PNG / JPEG / BMP / TLG(TLG5/TLG6) / PSB（捆绑在 layer 解码链路里）。
- **OpenGL 离屏合成**（ANGLE）：引擎合成到一张纹理，再零拷贝丢给 Flutter 显示。

### 3.3 内置插件（`cpp/plugins`）
| 插件 | 作用 |
|------|------|
| `psb` | PSB 图层动画（吉里吉里独有的动画文件） |
| `psd` | 读取/解析 PSD 文件 |
| `layerex` / `layerExDraw` | KAGEX 图层扩展 |
| `motionplayer` | 逐帧动画播放 |
| `fstat` | 文件状态查询（部分游戏脚本需要） |
| `cubism` (Live2D) | 按 SDK 是否在磁盘选择性编译 |
| `drawDeviceD2DCompat` | "包装型 draw device"范例（`__captureBaseDrawDevice` 挂点） |
| `krkrgles` | EGL/GLES 平台兼容插件 |

### 3.4 音频 / 视频
- 音频：WAV / OGG(Vorbis) / Opus 解码，BGM、SE、语音。
- 视频：`krmovie`（基于 ffmpeg），解码链路已就位，画面合成 Present 尚在待办（见
  [todo.md](todo.md)）——大多数游戏用不到，只在播 OP/影片时相关。

### 3.5 尚未内置（Z 时代插件缺口）
这是一款 KRKRZ（吉里吉里Z）游戏可能会需要的，我们**还没做**、目前会提示 `Failed`：
`drawdeviceD3DZ`、`kztouch`、`k2compat`、`kagexopt`、`multiimage`、`squirrel`。
这正是"与 Z 闭源版兼容持平"的目标项，详见 [todo.md](todo.md)。

---

## 四、怎么把它跑起来？

### 环境要求
| 目标 | 需要 |
|------|------|
| iOS | macOS + Xcode |
| Android | Windows/macOS/Linux + **ANDROID_NDK_HOME** |
| macOS | macOS + Xcode |
| Windows 调试 | Windows + MinGW（CMakePresets 里有 `Windows MinGW Config`） |

### 一键构建
```bash
./build.sh ios release     # iOS → 无签名 IPA（侧载测试用）
./build.sh android debug   # Android → APK
./build.sh macos debug     # macOS → App
```

### 手动 / 平台预设
```bash
# Linux 引擎验证（CI 用）
cmake --preset "Linux Debug Config" && cmake --build --preset "Linux Debug Build"

# Windows（MinGW 宿主跑引擎，做对照/调试黑屏等很好用）
cmake --preset "Windows MinGW Config" && cmake --build --preset "Windows MinGW Config"
```

> 💡 **小白提示**：如果只想快速"能不能跑"，优先用 **Windows MinGW 或 Linux 预设**编译引擎，
> 比开 iOS/Android 快得多，也方便对比"同一款游戏在 PC 上黑不黑"。

---

## 五、怎么往里面装一款游戏？

在 App 里（`apps/flutter_app/lib/pages/home_page.dart`）：
1. **导入**：选一个游戏**目录** 或 一个 `.xp3` 文件。
   - 目录型：目录里要有启动脚本（`startup.tjs`），或者至少含 `.xp3` 包（引擎会自动挂载）。
   - 单包型：直接选那个 `xxx.xp3`。
2. **目录 ⇄ 单包互转**（工具按钮）：目录可"打包为 XP3"，`.xp3` 可"解包 XP3"。
   - "打包为 XP3" = 把整个游戏目录递归收进一个 `.xp3`（**不压缩/RAW**，仅聚合）。
   - "解包 XP3" = 把 `.xp3` 还原成一个目录。两者互为逆操作。
3. 点进游戏，引擎启动并开始渲染。

---

## 六、怎么排错？（小白最先学的三件事）

### 1. 日志在哪看
引擎会把日志写到沙盒内的日志文件（iOS 在 Documents 下，如 `krkr2_engine.log`）。
每一行格式大致：
```
[时间] [core|tjs2] [info|debug|warning|error] 消息内容
```
- `[info] ... Loading Plugin: x.dll Success/Failed` —— 哪个插件成/败。
- `[error] Cannot open storage ...` —— 文件打不开。
- 探针日志（黑屏诊断）：`FlutterWindowLayer::BlackScreen ...`、`SourceSample`、`PostBlit`。

### 2. 一个常见套路：先看"能不能走到标题"
游戏卡黑屏/白屏时，先看日志有没有走到：
```
startup.tjs → system/Initialize.tjs → first.ks → title.ks
```
走到 title.ks 表示脚本没问题；之后才需要查渲染/插件（如 Z 兼容黑屏）。

### 3. 用探针
我们在关键渲染点**内置了可开关的采样探针**（`SourceSample/PostBlit/draw/BlackScreen`，默认关闭，
`cmake -DENABLE_RENDER_PROBE=ON` 打开），专门用来区分"引擎没画" vs "画了但没进纹理"。
黑屏/渲染问题排查请看 [rendering-diagnosis.md](rendering-diagnosis.md)。

---

## 七、开发指导（改代码的正确姿势）

1. **先读文档**：根目录 [AGENTS.md](../../AGENTS.md)（AI 首屏指令）→
   [docs/dev/README.md](README.md)（索引）→ [conventions.md](conventions.md)（约定与陷阱，**最重要**）。
2. **改动前先看约定**：尤其"平台守卫别删""`win32/` 是共享实现不能删""SIMD 以标量为准"。
3. **改完要同步文档**：本项目的文档和代码是绑定的，改代码请一并更新相关 md。
4. **改动请标注理由 + 手动 git commit**（语气是为协作分支准备的，提交信息写清楚"为什么"）。
5. **待办看 [todo.md](todo.md)**：动手前先看有没有现成条目，避免重复。

### 常用"入口文件"速查
| 想干嘛 | 看哪 |
|--------|------|
| 找关键函数/符号在哪 | [key-references.md](key-references.md) |
| 构建/CI/产物 | [build.md](build.md) |
| 渲染数据流 | [architecture.md](architecture.md) |
| 当前没做完的事 | [todo.md](todo.md) |

---

## 八、理解原理：一帧是怎么画出来的（教学向）

```
事件循环每帧：
1. TJS 脚本改图层（改背景/立绘/文字/位置）
2. 引擎把这些图层"合成"到一块内存纹理（主 DrawBuffer）
   └─ UpdateToDrawDevice → CompleteForWindow → 把图层子树依次 blit 进 DrawBuffer
3. BasicDrawDevice::Show() 把 DrawBuffer 的纹理交给窗口
4. FlutterWindowLayer::UpdateDrawBuffer() 把它 blit 到 IOSurface/纹理 → Flutter 显示
```

- **零拷贝**：移动端走 GPU 直通（`GetNativeGLTextureId()` 非 0），省去 CPU 来回搬像素。
- **黑屏判断**：一块从未被合成过的 DrawBuffer 初始就是**不透明黑（0xFF000000）**——
  如果你在日志里看到源纹理始终是 `(0,0,0,255)` 且 draw 计数不涨，说明"合成这一步没发生"，
  往往是绘图设备/插件（如 Z 的 drawdevice）没接上，而不是普通渲染 bug。

---

> 🔗 下一篇：[developers-guide.md](developers-guide.md)（人类开发者入门）。