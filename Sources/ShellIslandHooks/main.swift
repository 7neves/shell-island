import Darwin
import Foundation

/// ShellIslandHooks — Claude Code Hook CLI 转发进程
///
/// Claude Code 通过 settings.json 中的 hooks 配置调用此 CLI：
/// 1. 从 stdin 读取 ClaudeHookPayload JSON
/// 2. 连接到 BridgeServer Unix socket（主 App 进程内）
/// 3. 转发事件，等待 AppModel 处理
/// 4. 将响应写入 stdout（Claude Code 读取）
///
/// PermissionRequest 超时 24 小时（等用户操作），其余事件 45 秒后 fail-open。

// MARK: - Shared Types (bundle with CLI, mirrors ShellIslandCore)

enum ClaudeHookEventName: String, Codable {
    case sessionStart = "SessionStart"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
}

struct ClaudeHookPayload: Codable {
    let session_id: String
    let transcript_path: String?
    let cwd: String?
    let permission_mode: String?
    let hook_event_name: String
    let model: String?
    let source: String?
    let tool_name: String?
    let tool_input: ClaudeHookJSONValue?
    let prompt: String?
    let terminal_tty: String?
    let permission_suggestions: [ClaudePermissionSuggestion]?

    var eventName: ClaudeHookEventName? {
        ClaudeHookEventName(rawValue: hook_event_name)
    }
}

/// JSON 递归值类型（与 ShellIslandCore.ClaudeHookJSONValue 镜像）
enum ClaudeHookJSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: ClaudeHookJSONValue])
    case array([ClaudeHookJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([String: ClaudeHookJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([ClaudeHookJSONValue].self) {
            self = .array(value)
        } else if container.decodeNil() {
            self = .null
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

struct ClaudePermissionSuggestion: Codable {
    let behavior: String
    let reason: String?
}

struct BridgeRequest: Codable {
    let id: String
    let event: String
    let payload: ClaudeHookPayload

    init(id: String, event: ClaudeHookEventName, payload: ClaudeHookPayload) {
        self.id = id
        self.event = event.rawValue
        self.payload = payload
    }
}

struct BridgeResponse: Decodable {
    let id: String
    let decision: ClaudePermissionDecision?
}

struct ClaudePermissionDecision: Codable {
    let behavior: String
    let reason: String?
}

struct HookOutput: Encodable {
    let hookSpecificOutput: HookSpecificOutput

    init(eventName: String, decision: String, reason: String?) {
        self.hookSpecificOutput = HookSpecificOutput(
            hookEventName: eventName,
            permissionDecision: decision,
            permissionDecisionReason: reason
        )
    }
}

struct HookSpecificOutput: Encodable {
    let hookEventName: String
    let permissionDecision: String
    let permissionDecisionReason: String?
}

/// Socket 路径（与 BridgeTransport 保持一致）
func socketPath() -> String {
    NSHomeDirectory() + "/Library/Application Support/ShellIsland/bridge.sock"
}

/// 写入 Data 到文件描述符（处理 EINTR/EAGAIN）
func writeAll(_ data: Data, to fd: Int32) -> Bool {
    let total = data.count
    var written = 0
    while written < total {
        let n = data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> Int in
            guard let base = buf.baseAddress else { return -1 }
            return write(fd, base.advanced(by: written), total - written)
        }
        if n > 0 { written += n }
        else if n < 0 {
            if errno == EAGAIN || errno == EINTR { continue }
            return false
        } else { return false }
    }
    return true
}

/// 写入 HookOutput 到 stdout
func writeOutput(_ output: HookOutput) {
    guard var data = try? JSONEncoder().encode(output) else { return }
    data.append(0x0A)
    _ = writeAll(data, to: STDOUT_FILENO)
}

/// 连接到 BridgeServer，发送请求并等待响应
func sendViaSocket(payload: ClaudeHookPayload, timeout: TimeInterval) -> BridgeResponse? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }

    // SO_NOSIGPIPE
    var opt: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

    // 构建 sockaddr_un
    let path = socketPath()
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { dest in
        dest.withMemoryRebound(to: Int8.self, capacity: pathBytes.count) { destBytes in
            pathBytes.withUnsafeBytes { srcBytes in
                memcpy(destBytes, srcBytes.baseAddress!, srcBytes.count)
            }
        }
    }

    let addrPtr = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
    }

    guard connect(fd, addrPtr, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0 else {
        return nil
    }

    // 构建请求
    guard let eventName = payload.eventName else { return nil }
    let requestId = UUID().uuidString
    let request = BridgeRequest(id: requestId, event: eventName, payload: payload)

    guard var requestData = try? JSONEncoder().encode(request) else { return nil }
    requestData.append(0x0A)

    // 写入请求
    guard writeAll(requestData, to: fd) else { return nil }

    // 等待响应
    let deadline = Date().addingTimeInterval(timeout)
    var buffer = Data()
    while true {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { return nil }

        var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pollRet = poll(&pollFd, 1, Int32(min(remaining, 1.0) * 1000))
        if pollRet < 0 {
            if errno == EINTR { continue }
            return nil
        }
        if pollRet == 0 { continue }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        if n > 0 {
            buffer.append(contentsOf: buf[0..<n])
            if buffer.contains(0x0A) {
                guard let newlineIdx = buffer.firstIndex(of: 0x0A) else { return nil }
                let line = buffer.prefix(upTo: newlineIdx)
                return try? JSONDecoder().decode(BridgeResponse.self, from: Data(line))
            }
        } else if n == 0 {
            return nil
        } else {
            if errno == EAGAIN || errno == EINTR { continue }
            return nil
        }
    }
}

// MARK: - Entry Point

func main() {
    // 1. 读取 stdin
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard !input.isEmpty else {
        exit(0)
    }

    // 2. 解码 hook payload
    guard let payload = try? JSONDecoder().decode(ClaudeHookPayload.self, from: input) else {
        exit(0)  // fail-open
    }

    // 3. 判断超时
    let isPermissionRequest = payload.eventName == .permissionRequest
    let eventName = payload.hook_event_name
    let timeout: TimeInterval = isPermissionRequest ? 86400 : 45

    // 4. 发送到 BridgeServer
    guard let response = sendViaSocket(payload: payload, timeout: timeout) else {
        // Bridge 不可用，fail-open
        if isPermissionRequest {
            writeOutput(HookOutput(eventName: eventName, decision: "allow", reason: "ShellIsland bridge unavailable, fail-open"))
        }
        exit(0)
    }

    // 5. 写入 stdout（仅 PermissionRequest 需要输出，其他事件 exit 0 = continue）
    if isPermissionRequest, let decision = response.decision {
        writeOutput(HookOutput(eventName: eventName, decision: decision.behavior, reason: decision.reason))
    }
    // 非 PermissionRequest 事件：exit 0 即表示 continue，无需 stdout 输出
}

main()
