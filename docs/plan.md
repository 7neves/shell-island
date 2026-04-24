# ShellIsland v1 规划（macOS 13.7 / kitty / 刘海胶囊）

## Summary
从零开始做一个 **macOS 13.7.7** 兼容的常驻型桌面工具 `ShellIsland`，专门占用屏幕中上方刘海下区域。默认显示为收起胶囊，左侧是状态，右侧是任务数量；点击后展开任务列表。  
v1 范围锁定为：

- 仅优先支持 **kitty**
- 仅识别 `brew`、`codex`、`npm run`
- 收起态始终可见，包含你要的 **复古像素/马赛克风格**
- 右侧数字 **只统计运行中的任务**
- 已完成/失败任务继续保留在展开列表里，直到手动清理
- 支持两类快捷操作：**打开对应 kitty 窗口/标签**、**结束任务**
- 登录自启动做成 **设置开关**，默认关闭

## Key Changes
### 1. 应用形态与系统集成
- 用 **Swift + SwiftUI + AppKit** 做原生 macOS 应用，目标 `macOS 13.7`，开发基线按当前环境 `Xcode 15.2`。
- 应用采用 **agent app** 形态（无 Dock 常驻图标），主 UI 是一个自定义 `NSPanel`/浮动窗，固定在当前菜单栏所在屏幕的顶部中央；有刘海时贴近刘海下方，无刘海时保持顶部中间。
- 浮层默认收起为胶囊，点击展开任务面板；设置入口放在展开面板里。
- 请求 **Accessibility** 权限用于窗口激活/聚焦；不依赖屏幕录制权限。
- 登录自启动用 `SMAppService` 实现，作为设置项暴露。

### 2. 任务监控与状态模型
- 监控逻辑只跟踪 **kitty 进程树**，通过系统进程 API（`libproc` / `proc_pidinfo`）递归扫描 kitty 关联的 shell/子进程。
- 只识别三类根任务：
  - `brew`
  - `codex`
  - `npm run ...`
- 过滤规则：
  - `npm` 仅在参数中包含 `run` 时记为任务
  - shell 包装层（如 `zsh -c`）不直接记为任务
  - helper/子子进程不单独记任务，归属到最外层匹配命令
- 任务唯一键固定为 `pid + processStartTime`，避免 PID 复用误判。
- 任务状态统一为：
  - `running`
  - `succeeded`
  - `failed`
  - `terminated`
- 收起胶囊右侧数字仅显示 `running` 数量。
- 完成/失败/被终止的任务保留在展开列表中，直到用户点 `Clear Completed`；这些保留项不计入右侧数字。
- 默认轮询频率定为 **1 秒**，保证感知及时且不过度耗电。

### 3. kitty 精确跳转与结束任务
- “打开对应终端”按你的选择，定义为 **精确跳回对应 kitty 窗口/标签**，因此把 **kitty remote control** 作为前置条件。
- v1 明确要求用户在 kitty 配置中开启 `allow_remote_control yes`；应用启动时检查 `kitty @ ls` 是否可用。
- 若 remote control 未配置：
  - 顶部/设置页展示 setup blocker
  - 监控功能可继续工作
  - “打开对应终端”按钮禁用并给出配置指引
- 任务与 kitty 窗口/标签的映射使用：
  - `kitty @ ls` 返回的窗口/标签树
  - 进程 PID / 前台进程信息 / TTY 关联做匹配
- “结束任务”行为：
  - 先发 `SIGTERM`
  - 超时（默认 3 秒）后再发 `SIGKILL`
  - UI 立即进入 `terminating` 过渡态，最终落到 `terminated`

### 4. UI 与像素风规范
- 收起胶囊在所有状态下都采用像素风，不只 Idle：
  - 左侧：像素状态区
  - 右侧：像素数字
- Idle 态按你的要求做一个 **简易马赛克动画**，右侧显示像素风 `0`。
- 运行态左侧展示像素风运行指示；成功/失败用不同像素色块/小图案区分。
- 展开列表每项至少展示：
  - 命令名（`brew` / `codex` / `npm run <script>`）
  - 状态
  - 已运行时长或结束结果
  - `Open` / `Stop` 操作
- 展开列表底部提供：
  - `Clear Completed`
  - `Launch at Login` 开关
  - 权限/kitty 配置状态提示

### 5. 需要定义的内部接口/类型
实现时固定以下核心模型，避免边做边改：
- `TaskDefinition`
  - `kind: brew | codex | npmRun`
  - `displayName`
  - `matchRule`
- `ObservedTask`
  - `id`
  - `kind`
  - `pid`
  - `startTime`
  - `status`
  - `commandLine`
  - `tty`
  - `sessionRef`
  - `startedAt`
  - `endedAt`
  - `exitCode`
- `TerminalSessionRef`
  - `terminalApp = kitty`
  - `kittyWindowId`
  - `kittyTabId`
  - `tty`
- `AppPreferences`
  - `launchAtLogin`
  - `pollIntervalSeconds`
  - `keepCompletedUntilManualClear = true`
- `SetupState`
  - `accessibilityGranted`
  - `kittyRemoteControlReady`

## Test Plan
- 在 macOS 13.7.7 上验证应用可正常启动，顶部胶囊稳定居中显示。
- 无任务时显示 Idle 像素动画，右侧数字为 `0`。
- 分别启动 `brew`、`codex`、`npm run dev`，确认都能被识别并进入 `running`。
- 同时运行多个任务，确认右侧数字正确递增，只统计运行中项。
- 任务成功结束后保留在展开列表，状态正确变为 `succeeded`，右侧数字递减。
- 故意制造失败任务，确认显示 `failed` 且保留到手动清理。
- 点击 `Stop` 时先温和结束，再在超时后强制结束，状态落到 `terminated`。
- `kitty` 开启 remote control 时，`Open` 能精确跳到对应窗口/标签。
- `kitty` 未开启 remote control 时，应用明确提示缺少配置，且禁用 `Open`。
- 切换 `Launch at Login` 开关后，设置状态能正确持久化。
- 在无刘海屏或外接显示器上，胶囊仍保持顶部中央，不因机型差异错位。

## Assumptions
- 当前是 **greenfield** 项目，没有现成工程需要兼容。
- v1 发行方式按 **非 Mac App Store、非沙盒化** 方案规划，以避免进程观测和窗口控制受限。
- v1 不做 Terminal/iTerm2/Warp 兼容，只做 **kitty**，但代码结构按可扩展到更多终端设计。
- v1 不做任务历史持久化；“保留直到手动清理”仅针对当前应用运行周期。
- 若后续要扩到“任何终端”，下一阶段再抽象 `TerminalAdapter`，把 kitty 适配器从核心监控器中分离。
