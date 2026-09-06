# KrKr2 Next — 渲染 / 黑屏诊断方法（探针）

> 本文教你怎么用引擎内置的**渲染探针**来定位"黑屏 / 画面没更新 / 视频播不出"一类问题。
> 适用人群：开发者、AI Agent、以及遇到渲染问题的测试者。

---

## 一、什么时候用探针？

- 游戏启动后**黑屏 / 白屏 / 一直停在某一帧**；
- 画面某一块该显示却空白，或 **OP/标题影片没画面**；
- 需要区分"**引擎没画**" vs "**画了但没送进显示纹理**"。

探针是**诊断工具**，不是常驻功能：默认关闭，平时跑游戏零开销、零刷屏。

---

## 二、怎么打开探针？（默认关闭）

探针由编译期宏 `KRKR_RENDER_PROBE` 控制，**默认 OFF**。

方式〇（CI 打包，最省事）：iOS / Android 打包工作流的 **workflow_dispatch 手动触发**下
就有专门的开关，每次运行单独勾选，不用改代码、不用碰 CMake：
- `enable_render_probe=true` → 这次打包开启探针（默认 `false`）；
- `log_level` → 单独选引擎日志级别（默认 `auto`=按构建类型：release→info、debug→debug）。
- 排查黑屏：勾上探针 + `log_level=debug`（或 `trace`）跑一次，抓日志即可，测完恢复默认。

方式一（本地构建，推荐，改 CMake 选项）：
```bash
cmake -DENABLE_RENDER_PROBE=ON <其余参数>          # 打开
cmake -DENABLE_RENDER_PROBE=OFF <其余参数>         # 关闭（默认）
cmake -DKRKR_LOG_LEVEL=debug <其余参数>            # 单独指定日志级别(trace|debug|info|warn|err|critical|off)
```
（在 [CMakeLists.txt](../../CMakeLists.txt) 顶层 `add_compile_definitions(KRKR_RENDER_PROBE)`；
日志级别经 `KRKR_LOG_LEVEL_NUM` 注入 engine_api.cpp，可独立于 debug/release。）

方式二（临时，直接在某处全局定义）：
```c
#define KRKR_RENDER_PROBE
```

关掉后：`SourceSample / PostBlit / IOSurfacePixelSample / BlackScreen` 全部不编译，零性能/日志影响。

---

## 三、探针都打些什么？（对照表）

| 日志前缀 | 位置 | 含义 |
|----------|------|------|
| `FlutterWindowLayer::UpdateDrawBuffer` | 引擎渲染 → Flutter 纹理 | `path=GPU/CPU`、`srcTex/blitTex`、`layers`、`draw`（自上次统计以来的合成次数） |
| `FlutterWindowLayer::SourceSample` | 读引擎**源纹理** 25 点 | `nonBlack/25` + `avg(R,G,B,A)`：引擎合出来的画面有没有内容 |
| `FlutterWindowLayer::PostBlit` | blit 到显示目标后 | `err`（GL 错误）、`center(R,G,B,A)`：blit 是否成功写入 |
| `IOSurfacePixelSample` | 读共享 **IOSurface** 25 点 | `nonBlack/25` + `avg`：画面有没有真的到达 IOSurface |
| `FlutterWindowLayer::BlackScreen` | 连续黑屏且引擎在画 | `draw`、`layers`、`VideoOverlay total/active/playing`：判定黑屏是否与视频相关 |
| `VideoOverlay.Open` | 脚本打开影片 | `mode=overlay/layer/mixer` + `file=...`：游戏有没有真的去播片 |

> `avg=(0,0,0,255)` = **不透明纯黑**（通常等于主 DrawBuffer 从未被合成的初始色 `0xFF000000`）。
> `avg=(0,0,0,0)` = 透明黑（内容区域是空的）。

---

## 四、怎么靠日志判断问题在哪一端？（二分法）

黑屏时按顺序看这几条，就能把"坏在哪一段"圈出来：

1. **`SourceSample` 有没有色**（源纹理）：
   - **非黑** → 引擎合成是好的；再看 `PostBlit` / `IOSurfacePixelSample`（显示链路）。
   - **全黑** → 引擎主合成没产出；继续看 `draw` 和 `VideoOverlay`（见第 2 步）。
2. **`draw` 计数在涨吗？**
   - **在涨** → 引擎在持续合成，黑的是"图层内容本身"或"没画进源纹理"。
   - **卡住不涨**（且 `layers` 很多、TJS 还在跑）→ 像本文附的真实案例：**主合成根本没被触发**，往往是**绘图设备/插件缺失**（见第 5 步）。
3. **`PostBlit` 的 `err`**：
   - `err=0x0` → blit 本身没 GL 错误；黑是因为源就是黑的。
   - 非 0 → blit 失败（shader/状态/RenderTarget 绑定问题）。
4. **`VideoOverlay total/active/playing`**：
   - `total=0` → 游戏压根没开视频，黑屏**不是视频**问题（别去做 krmovie Present）。
   - `playing=1` 且画面黑 → 才去查视频帧有没有合成（krmovie Present 路径）。
5. **`layers` 很多 + `draw` 不涨 + 脚本在跑的"黑屏"** → **绘图设备 / Z 插件缺口**的典型特征
   （对应 KRKRZ 游戏缺 `drawdeviceD3DZ / kztouch / k2compat` 等，主 DrawBuffer 从未被合成）。
   结合日志里的 `Loading Plugin: ... Failed` 一起看。

---

## 五、日志文件会"拉屎"吗？

不会无限涨。日志文件是**旋转文件**：写满 **4 MiB 自动轮转，保留 3 份**（约 12 MiB 封顶，
见 [engine_api.h](../../bridge/engine_api/include/engine_api.h) `engine_set_log_file_path`）。

另外 release 默认日志级别 = **info**（`bridge/engine_api/src/engine_api.cpp`
`EnsureRuntimeLoggersInitialized`），把之前 `[debug]` 级别的刷屏（如每次文件探测的
`GetLocallyAccessibleName`）都挡掉了，日志文件只留 info/error 等真正有用的行。
需要极详细排查时再临时放开 debug。

**为什么日志文件要留着**：线上/"小白不会复现"的渲染问题，靠的就是这份设备日志回传
来定位——这也是探针能发挥作用的载体。

---

## 六、诊断后记得

- 修完问题，**保持 `ENABLE_RENDER_PROBE` 为 OFF**（默认），别把探针留在常驻路径里。
- 把新发现的"现象 → 探针结论 → 根因"补充到 [todo.md](todo.md) 或本文档，方便下次复用。

---

### 附：真实案例（Z 兼容黑屏）
魔女的夜宴（sabbat_kr，KRKRZ 目录版）真机日志：
```
IOSurfacePixelSample: tick=465 size=1334x750 nonBlack=0/25 avg=(0,0,0,255)
BlackScreen: draw=35, layers=109 ... VideoOverlay: total=0 active=0 playing=0
```
→ `draw` 卡在 35、源纹理保持初始黑、`VideoOverlay total=0` → **不是视频**、**主合成从未被触发**
→ 根因锁定在 **Z(krkrz) 插件兼容**（缺 drawdeviceD3DZ 等），详见 [todo.md](todo.md)。