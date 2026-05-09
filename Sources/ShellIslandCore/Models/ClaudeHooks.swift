import Foundation

// MARK: - Hook Event Names

public enum ClaudeHookEventName: String, Sendable, Codable {
    case sessionStart = "SessionStart"
    case permissionRequest = "PermissionRequest"
    case stop = "Stop"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case notification = "Notification"
}

// MARK: - CLI → Server Request

struct BridgeRequest: Codable {
    let id: String
    let event: ClaudeHookEventName
    let payload: ClaudeHookPayload
}

// MARK: - Server → CLI Response

struct BridgeResponse: Codable {
    let id: String
    let decision: ClaudePermissionDecision?
}

// MARK: - Claude Code Hook Payload

public struct ClaudeHookPayload: Codable, Sendable {
    public let session_id: String
    public let transcript_path: String?
    public let cwd: String?
    public let permission_mode: String?
    public let hook_event_name: String
    public let model: String?
    public let source: String?
    public let tool_name: String?
    public let tool_input: ClaudeHookJSONValue?
    public let prompt: String?
    public let terminal_tty: String?
    public let permission_suggestions: [ClaudePermissionSuggestion]?

    public var eventName: ClaudeHookEventName? {
        ClaudeHookEventName(rawValue: hook_event_name)
    }
}

// MARK: - Permission Suggestion

public struct ClaudePermissionSuggestion: Codable, Sendable {
    public let behavior: String
    public let reason: String?
}

// MARK: - Permission Decision (response to Claude Code)

public struct ClaudePermissionDecision: Codable, Sendable {
    public let behavior: String  // "allow" | "deny"
    public let reason: String?

    public init(behavior: String, reason: String? = nil) {
        self.behavior = behavior
        self.reason = reason
    }

    public static let allow = ClaudePermissionDecision(behavior: "allow")
    public static let deny = ClaudePermissionDecision(behavior: "deny")
}

// MARK: - JSONValue (for tool_input)

public enum ClaudeHookJSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: ClaudeHookJSONValue])
    case array([ClaudeHookJSONValue])
    case null

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
