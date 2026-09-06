# KrKr2 Next — 待办 / 已知问题（AI Agent 协作队列）

> 本文件维护当前未完成或待验证的工程事项，供 AI Agent 与开发者交接。
> 每完成一项，把该条目移到「已完成」或直接删除，并在 [README.md](README.md) 的
> 目录索引中保持本文件引用。
> 完成某项并验证后，请同步更新根目录 [AGENTS.md](../../AGENTS.md) 的「当前状态」。

## 进行中 / 待验证

### 1. Z（krkrz/KIRIKIRI Z）插件兼容 — 移动端黑屏根因【高优】
- **现象**（真机日志 `sabbat_kr`/魔女的夜宴，目录版）：游戏正常启动到
  `startup→Initialize→first.ks→title.ks`，XP3 全挂载，脚本/图层照常（事件 2 万对象、
  9k ICC、内存 230MB+），但合成源纹理始终 `(0,0,0,255)` 纯黑、draw 计数卡死不再增长。
- **已排除**：黑屏探针 `VideoOverlay: total=0 active=0 playing=0` → **不是视频/krmovie**。
  源纹理 = 主 LayerManager 的 `DrawBuffer`（初始即 `0xFF000000`），等于**从未被合成过**
  → Z 游戏主画面走的是 Z 那条路径（D3D drawdevice / Z 层），我们没接入。
- **关联插件缺口**（real 游戏 `plugin/` 里这些全部 `Failed`，引擎无任何实现/stub）：
  `drawdeviceD3D.dll`、`drawdeviceD3DZ.dll`、`kztouch.dll`、`k2compat.dll`、
  `kagexopt.dll`、`multiimage.dll`、`squirrel.dll`、`PackinOne.dll`。
- **与主线目标的关联**：这正是 AGENTS 里"补全解析引擎、插件，目标与 Z 闭源版兼容持平"
  的核心项。
- **下一步**：
  1. 用 **Windows**（我们 CMakePresets 有 Windows MinGW 预设）跑同一游戏二分：
     Windows 也黑 → 引擎/Z 层问题；Windows 正常 → 才转 iOS 纹理链路。
  2. 在 `ncbAutoRegister` 内部编表里给 Z 插件**挂名**（先能 link 成功），再定位
     到底是 `drawdeviceD3DZ` / Z 主层合成缺哪一环导致主 DrawBuffer 不被合成。
- 参考：引擎主合成链 `BasicDrawDevice::Show→GetDrawBuffer→UpdateDrawBuffer`、
  `CompleteForWindow→InternalComplete2(_GPU)`、`__captureBaseDrawDevice` 包装挂点
  （见 `cpp/plugins/drawDeviceD2DCompat.cpp`）。

### 2. krmovie Present 未实现（视频解码 → 画面合成）【一般，非本次黑屏根因】
- 现状：ffmpeg 解码链路完整（`cpp/core/movie/ffmpeg/`），但
  `VideoPresentOverlay::PresentPicture` 及 overlay 合成到场景/纹理的路径仍是 stub
  （只打一条 warn，不渲染）。
- 备注：**已证实不是魔女的夜宴黑屏的原因**（`VideoOverlay total=0`）；保留为通用待办，
  供真正的视频 OP/影片游戏使用。
- 待办：评估并把解码帧 RGBA 合成到引擎场景（Mixer/Layer）或 Flutter 纹理。
- 参考：`cpp/core/visual/impl/VideoOvlImpl.cpp` 的 `EC_UPDATE` 处理与
  `iTVPVideoOverlay::PresentVideoImage` / `GetFrontBuffer` 契约。

### 3. runtime-restart 不支持（退出后无法直接开另一个游戏）
- 现象：首次开游戏正常；不杀进程、退出后再开另一款游戏报
  `Engine Error engine_open_game_async failed: result=-3, error=runtime restart is not supported yet`。
- 已做：Dart 侧 `_exitGame` 现在先 `engineDestroy()` 等销毁完成再 `pop`。
- 待办：真机验证该修复；若仍有问题，需支持引擎热重启或强制以新进程形态打开。

### 4. SIMD 公式逐模式修到位级一致（保正确回归）
- 背景：`tests/tvpgl_simd_compare` 已证实 **23 处 SIMD ≠ 标量**；
  PS 全系混合 / SubBlend_o / ScreenBlend 已先回退到 `*_c` 标量保证正确
  （`tvpgl_simd_init.cpp` 已注释对应注册）。
- 待办：逐模式修 `PsApplyAlpha` 舍入序、SubBlend_o/ScreenBlend alpha、Overlay/HardLight
  分支到与 `*_c` 位级一致，tests 逐模式验证后放回 SIMD 派发。

### 5. KAGEX / KAG 差异兼容（kagexopt 相关）
- 待办：调研并规划对依赖较新 KAG/KAGEX 行为或未登官方插件的游戏做兼容（确切需求待明确）。

### 6. multiimage（多图/psd 相关）支持
- 待办：规划 `multiimage`（多图像/图层处理）相关能力；确切范围与用例待明确后拆解。

### 7. 非标准目录结构（散装 xp3 启动定位）
- 现状：已支持标准 `data.xp3`/同目录 xp3 自动挂载（`TVPAutoMountProjectXP3Archives`）。
- 待办：验证形如 `D:\...\委員界の異端者體驗版`（体验版，目录内散装文件而非标准
  gameexe.dat/data.xp3 布局）的目录能否识别与启动；若不支持，补目录结构探测与启动文件定位。