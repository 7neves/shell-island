# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

ShellIsland 是一个 macOS 13.7+ 兼容的常驻型桌面工具，占用屏幕中上方刘海下区域。默认显示为收起胶囊，点击后展开任务列表。

- **技术栈**: Swift + SwiftUI + AppKit
- **目标平台**: macOS 13.7+
- **开发环境**: Xcode 15.2+
- **应用形态**: Agent app（无 Dock 常驻图标）

## 核心功能

- 监控 kitty 终端中的 `brew`、`codex`、`npm run` 任务
- 复古像素/马赛克风格 UI
- 收起态显示运行中任务数量
- 支持跳转到对应 kitty 窗口/标签、结束任务
- 登录自启动（可选）

## 项目结构

```
shell-island/
├── docs/           # 项目文档
│   └── plan.md     # v1 详细规划
├── scripts/        # 构建和运行脚本
└── ...
```

## 重要约定

### 代码架构
- Swift 文件尽量不超过 400 行
- 每层文件夹文件不超过 8 个
- 避免「坏味道」：僵化、冗余、循环依赖、脆弱性、晦涩性、数据泥团、不必要的复杂性

### 核心模型（必须遵循）

```swift
// 任务定义
enum TaskKind {
    case brew, codex, npmRun
}

// 观测到的任务
struct ObservedTask {
    let id: String           // pid + processStartTime
    let kind: TaskKind
    let pid: Int32
    let startTime: Date
    var status: TaskStatus   // running | succeeded | failed | terminated
    let commandLine: String
    let tty: String?
    var sessionRef: TerminalSessionRef?
    let startedAt: Date
    var endedAt: Date?
    var exitCode: Int32?
}

// 终端会话引用
struct TerminalSessionRef {
    let terminalApp = "kitty"
    let kittyWindowId: UInt64
    let kittyTabId: UInt64
    let tty: String
}

// 应用偏好
struct AppPreferences {
    var launchAtLogin: Bool
    var pollIntervalSeconds: Double = 1.0
    let keepCompletedUntilManualClear = true
}

// 设置状态
struct SetupState {
    var accessibilityGranted: Bool
    var kittyRemoteControlReady: Bool
}
```

## 开发须知

### 前置条件
- 用户必须在 kitty 配置中开启 `allow_remote_control yes`
- 应用需要 Accessibility 权限用于窗口激活/聚焦
- 不需要屏幕录制权限

### 关键技术点
- 进程监控：使用 `libproc` / `proc_pidinfo` 递归扫描 kitty 进程树
- 任务识别：只识别 `brew`、`codex`、`npm run`（npm 仅在参数包含 `run` 时记为任务）
- 轮询频率：默认 1 秒
- 结束任务：先 `SIGTERM`，3 秒超时后 `SIGKILL`
- 登录自启动：使用 `SMAppService`

### UI 规范
- 收起胶囊始终采用像素风格
- 左侧：像素状态区
- 右侧：像素数字（仅统计 running 数量）
- Idle 态显示简易马赛克动画
- 展开列表包含：命令名、状态、时长/结果、Open/Stop 操作
- 展开列表底部：Clear Completed、Launch at Login 开关、配置状态提示

## v1 范围边界

- ✅ 仅支持 kitty 终端
- ✅ 仅识别 brew、codex、npm run
- ✅ 任务保留直到手动清理（当前运行周期内）
- ✅ 非 Mac App Store、非沙盒化
- ❌ 不支持 Terminal/iTerm2/Warp
- ❌ 不做任务历史持久化
