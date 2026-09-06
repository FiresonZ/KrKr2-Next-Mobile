# KrKr2 Next — 待办 / 已知问题（AI Agent 协作队列）

> 本文件维护当前未完成或待验证的工程事项，供 AI Agent 与开发者交接。
> 每完成一项，把该条目移到「已完成」或直接删除，并在 [README.md](README.md) 的
> 目录索引中保持本文件引用。
> 完成某项并验证后，请同步更新根目录 [AGENTS.md](../../AGENTS.md) 的「当前状态」。

## 进行中 / 待验证

### 1. 黑屏根因确认（含脚本探针）
- 现象：iOS 启动后画面淡出为黑屏，引擎仍在绘制（`draw>0`）但 blit 源纹理采样全黑。
- 已加诊断/探针：
  - `ui_stubs.cpp::UpdateDrawBuffer` 的 `SourceSample` / `PostBlit` / 绘制计数（`draw`）采样；
  - 本次新增 `FlutterWindowLayer::BlackScreen` 探针：连续 3 次「引擎在画 + 源纹理黑」
    时，调用 `tTJSNI_VideoOverlay::DumpDebugStats()` 打印当前 video overlay 是否在播。
- **工作假设**：游戏在等 krmovie 视频（op/ed 或 CG）完成，而 krmovie Present 路径仍被
  stub（见下），导致画面停在淡出后的黑帧。
- 待办：真机读取日志，确认 `BlackScreen` 探针中 `VideoOverlay ... playing` 是否为真；
  据此决定是否优先实现 krmovie Present。

### 2. krmovie Present 未实现（视频解码 → 画面合成）
- 现状：ffmpeg 解码链路完整（`cpp/core/movie/ffmpeg/`），但
  `VideoPresentOverlay::PresentPicture` 及 overlay 合成到场景/纹理的路径仍是 stub
  （只打一条 warn，不渲染）。
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