import Darwin
import Foundation

// MARK: - Client Connection (internal to server)

private final class ClientConnection: @unchecked Sendable {
    let fd: Int32
    let requestId: String
    let sessionID: String

    init(fd: Int32, requestId: String, sessionID: String) {
        self.fd = fd
        self.requestId = requestId
        self.sessionID = sessionID
    }
}

// MARK: - BridgeServer

public final class BridgeServer: @unchecked Sendable {
    private let socketPath: String
    private let logger = ShellLogger(category: "BridgeServer")
    private let lock = NSLock()

    private var serverFD: Int32 = -1
    private var source: DispatchSourceRead?
    private var isRunning = false

    /// sessionID → ClientConnection (pending permission requests)
    private var pendingBySession: [String: ClientConnection] = [:]

    /// requestID → ClientConnection
    private var pendingByRequest: [String: ClientConnection] = [:]

    /// 匹配 taskID → sessionID
    private var taskToSession: [String: String] = [:]

    // MARK: - Callbacks

    public var onHookEvent: ((ClaudeHookPayload) -> Void)?

    // MARK: - Init

    public init(socketPath: String = BridgeTransport.socketPath) {
        self.socketPath = socketPath
        BridgeTransport.disableSigPipe()
    }

    // MARK: - Start / Stop

    public func start() throws {
        guard !isRunning else { return }

        let fd = try BridgeTransport.createBoundSocket()
        isRunning = true
        serverFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .utility))
        src.setEventHandler { [weak self] in
            self?.handleAccept()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            close(self.serverFD)
            BridgeTransport.cleanupSocketFile()
        }
        src.resume()
        source = src

        logger.info("BridgeServer 已启动: \(socketPath)")
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        source?.cancel()
        source = nil
        serverFD = -1

        lock.lock()
        // 给所有 pending 客户端返回 allow（fail-open），与 CLI 超时行为保持一致
        for (_, client) in pendingBySession {
            _ = sendResponse(to: client, decision: .allow)
            close(client.fd)
        }
        pendingBySession = [:]
        pendingByRequest = [:]
        taskToSession = [:]
        lock.unlock()

        logger.info("BridgeServer 已停止")
    }

    // MARK: - Permission Resolution (called from AppModel on main actor)

    /// 根据 taskID 解析 permission 请求，返回 true 表示响应已成功发送
    @discardableResult
    public func resolvePermission(taskID: String, behavior: String) -> Bool {
        lock.lock()
        guard let sessionID = taskToSession[taskID],
              let client = pendingBySession[sessionID] else {
            lock.unlock()
            logger.warning("resolvePermission: 未找到 taskID=\(taskID) 的 pending 请求")
            return false
        }
        // 清理
        pendingBySession.removeValue(forKey: sessionID)
        pendingByRequest.removeValue(forKey: client.requestId)
        taskToSession.removeValue(forKey: taskID)
        lock.unlock()

        let decision = ClaudePermissionDecision(behavior: behavior, reason: "User responded")
        let ok = sendResponse(to: client, decision: decision)
        close(client.fd)
        logger.info("Permission resolved: taskID=\(taskID) behavior=\(behavior) sent=\(ok)")
        return ok
    }

    // MARK: - Task-Session Mapping

    /// 注册 taskID → sessionID 映射（由 AppModel 在匹配后调用）
    public func register(taskID: String, forSession sessionID: String) {
        lock.lock()
        taskToSession[taskID] = sessionID
        lock.unlock()
    }

    /// 清除指定 task 的 hook 状态（Stop 事件时调用）
    public func clearTask(_ taskID: String) {
        lock.lock()
        if let sessionID = taskToSession[taskID] {
            if let client = pendingBySession[sessionID] {
                _ = sendResponse(to: client, decision: nil)
                close(client.fd)
                pendingBySession.removeValue(forKey: sessionID)
                pendingByRequest.removeValue(forKey: client.requestId)
            }
        }
        taskToSession.removeValue(forKey: taskID)
        lock.unlock()
    }

    /// 检查指定 task 是否已被 hook 管理
    public func isTaskManagedByHook(_ taskID: String) -> Bool {
        lock.lock()
        let managed = taskToSession[taskID] != nil
        lock.unlock()
        return managed
    }

    // MARK: - Private: Accept Connections

    private func handleAccept() {
        var addr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = accept(serverFD, castToSockaddr(&addr), &addrLen)
        guard clientFD >= 0 else {
            if errno != EAGAIN && errno != EWOULDBLOCK {
                logger.error("accept 失败: errno=\(errno)")
            }
            return
        }

        BridgeTransport.setNonBlocking(clientFD)
        var opt: Int32 = 1
        _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        // 在新队列中处理此客户端（不阻塞 accept loop）
        let queue = DispatchQueue.global(qos: .utility)
        queue.async { [weak self] in
            self?.handleClient(fd: clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        // fdOwner 追踪 fd 生命周期：>= 0 时 defer 负责 close，
        // 设为 -1 表示所有权已转移（如 PermissionRequest 存入 ClientConnection）
        var fdOwner = fd
        defer {
            if fdOwner >= 0 { close(fdOwner) }
        }

        // 读取请求行（客户端应在连接后立即发送）
        guard let line = BridgeTransport.readLine(from: fd, timeout: 10) else {
            return
        }

        guard let request = try? BridgeTransport.decodeLine(line, as: BridgeRequest.self) else {
            logger.warning("客户端发送了无效的 JSON，关闭连接")
            return
        }

        let payload = request.payload
        guard let eventName = payload.eventName else {
            logger.warning("未知 hook 事件: \(payload.hook_event_name)")
            _ = BridgeTransport.writeLine(ackResponse(id: request.id), to: fd)
            return
        }

        logger.info("收到 hook 事件: \(eventName.rawValue) session=\(payload.session_id)")

        switch eventName {
        case .permissionRequest:
            fdOwner = -1  // 所有权转移给 ClientConnection
            handlePermissionRequest(request: request, fd: fd)
        case .stop:
            DispatchQueue.main.async { [weak self] in
                self?.onHookEvent?(payload)
            }
            _ = BridgeTransport.writeLine(ackResponse(id: request.id), to: fd)
        default:
            // SessionStart 等事件：通知 AppModel，发送 ack
            DispatchQueue.main.async { [weak self] in
                self?.onHookEvent?(payload)
            }
            _ = BridgeTransport.writeLine(ackResponse(id: request.id), to: fd)
        }
    }

    private func handlePermissionRequest(request: BridgeRequest, fd: Int32) {
        // PermissionRequest 需要等待用户响应，不立即关闭连接
        let client = ClientConnection(
            fd: fd,
            requestId: request.id,
            sessionID: request.payload.session_id
        )

        lock.lock()
        pendingBySession[request.payload.session_id] = client
        pendingByRequest[request.id] = client
        lock.unlock()

        // 通知 AppModel 匹配 task
        DispatchQueue.main.async { [weak self] in
            self?.onHookEvent?(request.payload)
        }
    }

    // MARK: - Private Helpers

    private func sendResponse(to client: ClientConnection, decision: ClaudePermissionDecision?) -> Bool {
        let response = BridgeResponse(id: client.requestId, decision: decision)
        guard let data = try? JSONEncoder().encode(response) else { return false }
        return BridgeTransport.writeLine(data, to: client.fd)
    }

    private func ackResponse(id: String) -> Data {
        let response = BridgeResponse(id: id, decision: nil)
        return (try? JSONEncoder().encode(response)) ?? Data()
    }

    private func castToSockaddr(_ ptr: UnsafeMutablePointer<sockaddr_un>) -> UnsafeMutablePointer<sockaddr> {
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
    }
}
