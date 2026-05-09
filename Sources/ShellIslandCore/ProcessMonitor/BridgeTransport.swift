import Darwin
import Foundation

/// Unix Socket 传输层工具
public enum BridgeTransport {
    /// Socket 文件路径
    public static var socketPath: String {
        let appSupport = NSHomeDirectory() + "/Library/Application Support/ShellIsland"
        return appSupport + "/bridge.sock"
    }

    /// 确保 Application Support 目录存在
    static func ensureAppSupportDir() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    // MARK: - NDJSON Codec

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)  // newline
        return data
    }

    static func decodeLines<T: Decodable>(_ data: Data, as: T.Type) throws -> [T] {
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        return try lines.map { line in
            try JSONDecoder().decode(T.self, from: Data(line))
        }
    }

    static func decodeLine<T: Decodable>(_ data: Data, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Socket Utilities

    /// 设置 socket 为非阻塞
    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
    }

    /// 忽略 SIGPIPE（写入断开连接时不会 crash）
    public static func disableSigPipe() {
        var one: Int32 = 1
        _ = withUnsafePointer(to: &one) { ptr in
            setsockopt(Int32(SIGPIPE), SOL_SOCKET, SO_NOSIGPIPE, ptr, socklen_t(MemoryLayout<Int32>.size))
        }
        signal(SIGPIPE, SIG_IGN)
    }

    /// 删除旧的 socket 文件
    static func cleanupSocketFile() {
        unlink(socketPath)
    }

    /// 创建并绑定 Unix domain socket
    static func createBoundSocket() throws -> Int32 {
        cleanupSocketFile()
        try ensureAppSupportDir()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw BridgeError.socketCreateFailed(errno: errno)
        }

        // SO_NOSIGPIPE: 写入断开连接时返回 EPIPE 而非 SIGPIPE
        var opt: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { dest in
            dest.withMemoryRebound(to: Int8.self, capacity: pathBytes.count) { destBytes in
                pathBytes.withUnsafeBytes { srcBytes in
                    memcpy(destBytes, srcBytes.baseAddress!, srcBytes.count)
                }
            }
        }
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        guard bind(fd, castToSockaddr(&addr), addrLen) == 0 else {
            let err = errno
            close(fd)
            throw BridgeError.bindFailed(errno: err)
        }

        guard listen(fd, 5) == 0 else {
            let err = errno
            close(fd)
            throw BridgeError.listenFailed(errno: err)
        }

        setNonBlocking(fd)
        return fd
    }

    // MARK: - Socket I/O

    /// 从 socket 读取直到 newline，返回 data（不含 newline）
    static func readLine(from fd: Int32, timeout: TimeInterval) -> Data? {
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
            if pollRet == 0 { continue }  // timeout, loop again
            guard pollFd.revents & Int16(POLLIN) != 0 else { return nil }

            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buf, buf.count)
            if n > 0 {
                buffer.append(contentsOf: buf[0..<n])
                if let newlineIdx = buffer.firstIndex(of: 0x0A) {
                    return buffer.prefix(newlineIdx)
                }
            } else if n == 0 {
                return nil  // EOF
            } else {
                if errno == EAGAIN || errno == EINTR { continue }
                return nil
            }
        }
    }

    /// 向 socket 写入 data + newline
    @discardableResult
    static func writeLine(_ data: Data, to fd: Int32) -> Bool {
        var toWrite = data
        toWrite.append(0x0A)
        let total = toWrite.count
        var written = 0
        while written < total {
            let n = toWrite.withUnsafeBytes { ptr -> Int in
                guard let base = ptr.baseAddress else { return -1 }
                return write(fd, base.advanced(by: written), total - written)
            }
            if n > 0 {
                written += n
            } else if n < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                return false
            } else {
                return false
            }
        }
        return true
    }

    private static func castToSockaddr(_ ptr: UnsafeMutablePointer<sockaddr_un>) -> UnsafeMutablePointer<sockaddr> {
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
    }
}

// MARK: - Errors

enum BridgeError: Error, LocalizedError {
    case socketCreateFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case acceptFailed(errno: Int32)

    var errorDescription: String? {
        switch self {
        case .socketCreateFailed(let e): return "Socket 创建失败 (errno=\(e))"
        case .bindFailed(let e): return "Socket bind 失败 (errno=\(e))"
        case .listenFailed(let e): return "Socket listen 失败 (errno=\(e))"
        case .acceptFailed(let e): return "Socket accept 失败 (errno=\(e))"
        }
    }
}
