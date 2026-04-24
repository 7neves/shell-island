# ShellIsland macOS 13.7 兼容性分析

## 概述

本文档分析参考项目 `open-vibe-island` (macOS 14+) 与目标项目 `ShellIsland` (macOS 13.7+) 之间的 API 兼容性差异，并提供适配方案。

## 版本对比

| 项目 | 最低版本 | Swift 版本 | Xcode 版本 |
|------|----------|-------------|------------|
| open-vibe-island | macOS 14.0 | Swift 6.2 | Xcode 15.2+ |
| ShellIsland | macOS 13.7 | Swift 5.9+ | Xcode 14.3+ |

## API 兼容性分析

### 1. NSScreen 安全区域 API

| API | 引入版本 | macOS 13.7 支持 | 适配方案 |
|-----|-----------|------------------|----------|
| `safeAreaInsets` | macOS 12.0 | ✅ 完全支持 | 直接使用 |
| `auxiliaryTopLeftArea` | macOS 12.0 | ✅ 完全支持 | 直接使用 |
| `auxiliaryTopRightArea` | macOS 12.0 | ✅ 完全支持 | 直接使用 |

**结论**: Notch 检测 API 完全兼容，无需适配。

### 2. AppKit 窗口管理 API

| API | 引入版本 | macOS 13.7 支持 | 适配方案 |
|-----|-----------|------------------|----------|
| `NSPanel` | macOS 10.0 | ✅ 完全支持 | 直接使用 |
| `level = .statusBar` | macOS 10.0 | ✅ 完全支持 | 直接使用 |
| `collectionBehavior` | macOS 10.7 | ✅ 完全支持 | 直接使用 |
| `ignoresMouseEvents` | macOS 10.0 | ✅ 完全支持 | 直接使用 |

**结论**: AppKit API 完全兼容，无需适配。

### 3. SwiftUI 特性

| 特性 | Swift 版本 | macOS 13.7 支持 | 适配方案 |
|------|-----------|------------------|----------|
| @Observable 宏 | Swift 5.9 | ✅ 支持 | 直接使用 |
| ObservableObject | Swift 5.1 | ✅ 支持 | 可用作备选 |
| @ObservationIgnored | Swift 5.9 | ✅ 支持 | 直接使用 |

**结论**: 核心 SwiftUI 特性完全支持。

### 4. 系统 API

| API | 引入版本 | macOS 13.7 支持 | 适配方案 |
|-----|-----------|------------------|----------|
| `NSWorkspace.shared.frontmostApplication` | macOS 10.0 | ✅ 支持 | 直接使用 |
| `NSRunningApplication` | macOS 10.0 | ✅ 支持 | 直接使用 |
| `NSEvent.addGlobalMonitorForEvents` | macOS 10.0 | ✅ 支持 | 直接使用 |
| `Process` | macOS 10.0 | ✅ 支持 | 直接使用 |
| `lsof` 命令 | 系统工具 | ✅ 支持 | 直接使用 |
| `ps` 命令 | 系统工具 | ✅ 支持 | 直接使用 |

**结论**: 系统 API 完全兼容。

### 5. 进程监控 API

| API | 引入版本/方案 | macOS 13.7 支持 | 适配方案 |
|-----|----------------|------------------|----------|
| `libproc` / `proc_pidinfo` | C API | ✅ 支持 | 通过 Swift interop 使用 |
| `kitty @` 命令 | kitty CLI | ✅ 支持 | 直接使用 |

**结论**: 进程监控方案完全兼容。

## 需要的适配点

### 1. Swift Package 配置

**参考项目**:
```swift
platforms: [
    .macOS(.v14),
]
```

**ShellIsland 适配**:
```swift
platforms: [
    .macOS(.v13),
]
```

### 2. Swift 语言版本

**参考项目**: Swift 6.2 (macOS 14 内置)
**ShellIsland**: Swift 5.9+ (macOS 13.7 支持)

**代码适配**:
- `@Observable` 宏在 Swift 5.9+ 可用，直接使用
- 某些 Swift 6.0+ 新特性需要避免
- 使用更保守的 Swift 编写方式

### 3. 外部依赖调整

**参考项目依赖**:
```swift
.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
```

**ShellIsland 适配**:
- 评估 `swift-markdown-ui` 在 macOS 13.7 的兼容性
- 评估 `Sparkle` 在 macOS 13.7 的兼容性
- 可能需要降级到更早的版本

## 具体适配示例

### 1. NSScreen 扩展（无需适配）

以下代码在 macOS 13.7 上完全正常工作：

```swift
extension NSScreen {
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }

        let notchHeight = safeAreaInsets.top
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftPadding - rightPadding + 4

        return CGSize(width: notchWidth, height: notchHeight)
    }
}
```

### 2. @Observable 使用（完全支持）

```swift
import Observation

@MainActor
@Observable
final class AppModel {
    var state = SessionState()
    @ObservationIgnored private var _cachedValue: Int = 0
}
```

### 3. 进程监控（完全支持）

```swift
import Foundation

struct ProcessMonitor {
    func discoverRunningProcesses() -> [ProcessInfo] {
        // 使用 ps 命令
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-Ao", "pid=,command="]

        // ... 执行和解析输出
    }
}
```

### 4. kitty remote control（完全支持）

```swift
struct KittyRemoteControl {
    func listWindows() throws -> [KittyWindow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/kitty")
        process.arguments = ["@", "ls"]

        // ... 执行和解析 JSON 输出
    }
}
```

## 兼容性验证清单

- [ ] NSScreen.safeAreaInsets 测试（有刘海和无刘海屏幕）
- [ ] NSScreen.auxiliaryTopLeftArea 测试
- [ ] NSScreen.auxiliaryTopRightArea 测试
- [ ] NSPanel 创建和显示测试
- [ ] 全局鼠标事件监听测试
- [ ] @Observable 状态变化测试
- [ ] 进程监控（ps/lsof）测试
- [ ] kitty remote control 集成测试
- [ ] 多显示器场景测试
- [ ] 外接显示器场景测试

## 潜在风险和注意事项

### 1. SwiftUI 版本差异

macOS 13.7 系统带的 SwiftUI 版本可能与 macOS 14+ 有差异：
- 某些新 UI 效果可能不可用
- 性能特性可能不同
- **缓解方案**: 使用基础 SwiftUI API，避免使用最新特性

### 2. 字体和渲染

不同 macOS 版本的系统字体可能略有差异：
- 像素风格渲染需要测试不同版本
- **缓解方案**: 使用自定义字体或嵌入字体资源

### 3. 系统行为差异

macOS 13.7 与 14+ 在以下方面可能有差异：
- Notch 区域的精确尺寸
- 窗口层级行为
- **缓解方案**: 使用安全区域 API 动态计算，而非硬编码

## 结论

### ✅ 好消息

**大部分 API 完全兼容**！参考项目的核心架构可以直接应用到 ShellIsland：

1. **Notch 检测 API** (safeAreaInsets 等) - macOS 12.0 引入，完全支持
2. **AppKit 窗口管理** - 完全支持
3. **@Observable 状态管理** - Swift 5.9+ 支持
4. **进程监控机制** - 通过系统命令，完全支持
5. **kitty 集成** - 完全支持

### ⚠️ 需要注意的点

1. **Swift Package 配置**: 改为 `.macOS(.v13)`
2. **外部依赖版本**: 可能需要降级某些第三方库
3. **Swift 保守编程**: 避免使用 Swift 6.0+ 独有特性
4. **测试覆盖**: 重点测试多显示器、外接显示器场景

### 🎯 建议的实现策略

1. **直接复用架构**: 参考项目的架构模式可以直接应用
2. **渐进式适配**: 先用基础 API 实现，后续逐步优化
3. **充分测试**: 在不同 macOS 版本和硬件配置上测试
4. **API 降级预案**: 对极少数不兼容 API 准备降级方案

---

**文档版本**: 1.0
**创建日期**: 2026-04-17
**适用项目**: ShellIsland v1
