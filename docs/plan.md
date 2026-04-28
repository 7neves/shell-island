# ShellIsland v1 规划（macOS 13.7 / kitty / 刘海胶囊）

## Summary
从零开始做一个 **macOS 13.7.7** 兼容的常驻型桌面工具 `ShellIsland`，专门占用屏幕中上方刘海下区域。默认显示为收起胶囊，左侧是状态，右侧是任务数量；点击后展开任务列表。  
v1 范围锁定为：

- 仅优先支持 **kitty**
- 仅识别 `brew`、`claude`（Claude Code）、`npm run`、`pnpm`、`yarn`
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
- 监控逻辑只跟踪 **kitty 进程树**，通过 `/bin/ps -Ao` 命令扫描系统进程，递归追溯 kitty 关联的 shell/子进程。
  - **技术债务**：计划使用 `libproc`/`proc_pidinfo` 系统 API，当前 v1 使用 `ps` 命令行实现。`ps` 方案在 1Hz 轮询下每次 fork 进程有额外开销，且命令行可能被截断。未来高负载或需沙盒化时应迁移到 `libproc`。
- 只识别以下任务类型：
  - `brew`
  - `claudeCode`（Claude Code，进程名 `claude`）
  - `npm run ...`
  - `pnpm`（pnpm 脚本执行）
  - `yarn`（yarn 脚本执行）
- 过滤规则：
  - `npm` 在参数中包含 `run` 或 `start` 时记为任务
  - `pnpm`/`yarn` 匹配 `run`/`start`/`dev`/`build`/`test` 等脚本别名
  - shell 包装层（如 `zsh -c`）不直接记为任务
  - helper/子子进程不单独记任务，归属到最外层匹配命令
  - 同一 TTY 上相同 TaskKind 的祖先进程会自动去重
- 任务唯一键为 **signature = TaskKind + workingDirectory + canonicalCommand**，而非 `pid + processStartTime`。
  - 这样设计是为了：同一工作目录 + 同一命令 → 映射到同一任务行，在展开列表中复用历史记录。
- 任务状态统一为：
  - `running` - 运行中
  - `terminating` - 正在终止（用户点击 Stop 后的过渡态）
  - `succeeded` - 成功完成
  - `failed` - 失败
  - `terminated` - 被用户终止
- 收起胶囊右侧数字仅显示 `running` 数量。
- 完成/失败/被终止的任务保留在展开列表中，直到用户点 `Clear Completed`；这些保留项不计入右侧数字。
- 轮询频率：有活动任务时使用 `preferences.pollIntervalSeconds`（默认 1 秒），无活动任务时使用 2 秒（降低空闲功耗）。
- **额外能力**：
  - **Attention 检测**：通过 kitty `get-text` 检测终端输出中的密码提示、`(y/n)` 确认等交互场景，在收起态和展开列表中以黄色 NEED 标记提醒用户。
  - **brew 失败推断**：brew 进程退出时无法直接获取退出码，通过扫描 Homebrew 日志文件和 kitty 终端输出来推断失败（检测 `Error:` 等关键字）。
  - **ReRun**：对已完成的历史 npm/pnpm/yarn 任务，支持一键重新运行（通过 kitty `send-text` 注入命令到原终端窗口）。
  - **系统资源监控**：展开面板底部显示 CPU 使用率、内存使用率、系统运行时长。

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
- “结束任务”行为（渐进式温和终止）：
  - 先发 `SIGINT`（模拟 Ctrl-C，对 Node 开发服务器等更友好）
  - 0.8 秒后若仍存活，发送 `SIGTERM`
  - 再 3 秒后若仍存活，发送 `SIGKILL`
  - UI 立即进入 `terminating` 过渡态（带脉冲动画），最终落到 `terminated`

### 4. UI 与像素风规范

收起胶囊共有三种 UI 状态：

**状态一：无任务状态（Idle）**
- 收起胶囊保持与刘海一致的窄宽度（`collapsedIdleScaleFactor = 1.0`），使用与有任务态相同的 `NotchShape.closed` 胶囊形状
- 面板显示为纯黑胶囊，不展示两侧内容（无状态图标、无数字），以无感知方式常驻在刘海区域
- 当任务出现时，胶囊平滑扩展至 1.3 倍刘海宽度以容纳图标和数字，形状保持不变

**状态二：有任务·收起状态（Collapsed Active）**
- 左侧：像素状态图标，根据任务状态动态切换：
  - 运行中 → 矩阵雨动画（蓝色）
  - 需关注（密码/确认输入）→ 消息图标（黄色）
  - 失败 → 警告图标（红色）
  - 全部成功 → 点阵图标（绿色）
- 右侧：像素数字，仅统计 `running` 状态的任务数量
- 点击胶囊 → 切换到展开状态

**状态三：展开状态（Expanded）**
- 面板从胶囊尺寸动画展开至 1.5 倍宽度/高度
- 顶部 header：左侧收起按钮（chevron.up）、右侧设置齿轮按钮
- Setup banner（权限/kitty 未就绪时显示）：提供快捷配置按钮
- 设置面板（齿轮按钮切换）：Launch at Login、权限状态、Kitty Remote 状态
- 任务列表：每项展示命令名、项目目录名、状态 Badge、已运行时长、Open/Stop/ReRun 操作
- 底部 HUD：CPU / MEM / UPTIME 三栏系统资源
- 点击面板外区域或收起按钮 → 回到收起状态

### 5. 需要定义的内部接口/类型
实现时固定以下核心模型，避免边做边改：
- `TaskKind`（枚举，替代原计划中的 `TaskDefinition`）
  - `case brew`
  - `case claudeCode`（进程名 `claude`，对应 Claude Code）
  - `case npmRun`
  - `case pnpmRun`
  - `case yarnRun`
  - `var displayName: String`
  - `func matches(command: String) -> Bool`（替代原计划中的 `matchRule`）
- `ObservedTask`
  - `id: String`（signature = kind + workingDirectory + canonicalCommand）
  - `kind: TaskKind`
  - `pid: Int32`
  - `startTime: Date`
  - `status: TaskStatus`
  - `commandLine: String`
  - `workingDirectory: String?`
  - `tty: String?`
  - `sessionRef: TerminalSessionRef?`
  - `startedAt: Date`
  - `endedAt: Date?`
  - `exitCode: Int32?`
- `TerminalSessionRef`
  - `terminalApp: String = "kitty"`
  - `kittySocketAddress: String?`（kitty remote control 的 socket 地址，如 `unix:/tmp/kitty`）
  - `kittyWindowId: UInt64`（kitty 顶层 OS 窗口 id）
  - `kittyTabId: UInt64`
  - `kittyLeafWindowId: UInt64`（kitty leaf window id，用于 focus-window 和 get-text）
  - `tty: String`
- `TaskStatus`（枚举）
  - `case running`
  - `case terminating`（用户点击 Stop 后的过渡态）
  - `case succeeded`
  - `case failed`
  - `case terminated`
- `AppPreferences`
  - `launchAtLogin: Bool`
  - `pollIntervalSeconds: Double`
  - `keepCompletedUntilManualClear: Bool = true`
- `SetupState`
  - `accessibilityGranted: Bool`
  - `kittyRemoteControlReady: Bool`
  - `var isReady: Bool`（两者皆 true 时为 ready）

## Test Plan
- 在 macOS 13.7.7 上验证应用可正常启动，顶部胶囊稳定居中显示。
- 无任务时显示纯黑胶囊（Idle 态，无状态图标，无数字）。
- 分别启动 `brew`、`claude`、`npm run dev`、`pnpm dev`、`yarn build`，确认都能被识别并进入 `running`。
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
