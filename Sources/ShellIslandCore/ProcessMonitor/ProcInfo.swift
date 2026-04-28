import Darwin
import Foundation

// MARK: - 数据模型

/// libproc 获取的进程信息（替换 RunningProcess）
public struct ProcProcessInfo: Sendable, Equatable {
    public let pid: Int32
    public let ppid: Int32
    public let tty: String           // 已归一化（如 "/dev/ttys000"），无 TTY 则为 "??"
    public let command: String       // 完整命令行（KERN_PROCARGS2 获取）
    public let workingDirectory: String?  // PROC_PIDVNODEPATHINFO 获取
}

// MARK: - 依赖注入类型

public typealias ProcListProvider = @Sendable () -> [ProcProcessInfo]
public typealias ProcParentPIDProvider = @Sendable (Int32) -> Int32?
public typealias ProcCommandProvider = @Sendable (Int32) -> String?

// MARK: - ProcInfo 结构体

public struct ProcInfo: Sendable {
    public let listAll: ProcListProvider
    public let parentPID: ProcParentPIDProvider
    public let processCommand: ProcCommandProvider

    public static let live = ProcInfo(
        listAll: { liveListAll() },
        parentPID: { liveParentPID($0) },
        processCommand: { liveProcessCommand($0) }
    )

    public init(
        listAll: @escaping ProcListProvider = { [] },
        parentPID: @escaping ProcParentPIDProvider = { _ in nil },
        processCommand: @escaping ProcCommandProvider = { _ in nil }
    ) {
        self.listAll = listAll
        self.parentPID = parentPID
        self.processCommand = processCommand
    }
}

// MARK: - libproc API 封装

/// 使用 sysctl(KERN_PROC_ALL) 获取全量进程列表（ps 内部使用的同一 API）
public func liveListAll() -> [ProcProcessInfo] {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    var bufSize: size_t = 0

    // 获取所需缓冲区大小
    guard sysctl(&mib, u_int(mib.count), nil, &bufSize, nil, 0) == 0, bufSize > 0 else {
        return []
    }

    let count = bufSize / MemoryLayout<kinfo_proc>.size
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)

    guard sysctl(&mib, u_int(mib.count), &procs, &bufSize, nil, 0) == 0 else {
        return []
    }

    let actualCount = bufSize / MemoryLayout<kinfo_proc>.size

    return procs.prefix(actualCount).compactMap { proc -> ProcProcessInfo? in
        let pid = proc.kp_proc.p_pid
        guard pid > 1 else { return nil }

        let ppid = proc.kp_eproc.e_ppid

        // 获取 TTY 名称
        let tty: String
        let e_tdev = proc.kp_eproc.e_tdev
        if e_tdev != 0 {
            if let namePtr = devname(e_tdev, S_IFCHR) {
                let name = String(cString: namePtr)
                tty = name.hasPrefix("/dev/") ? name : "/dev/\(name)"
            } else {
                tty = "??"
            }
        } else {
            tty = "??"
        }

        // 获取完整命令行 via KERN_PROCARGS2
        let command = getProcessCommandLine(pid)

        // 获取工作目录 via PROC_PIDVNODEPATHINFO
        let cwd = getProcessWorkingDirectory(pid)

        return ProcProcessInfo(
            pid: pid,
            ppid: ppid,
            tty: tty,
            command: command,
            workingDirectory: cwd
        )
    }
}

public func liveParentPID(_ pid: Int32) -> Int32? {
    var bsdInfo = proc_bsdinfo()
    let bsdSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard bsdSize > 0 else { return nil }
    return Int32(bsdInfo.pbi_ppid)
}

public func liveProcessCommand(_ pid: Int32) -> String? {
    var pathBuffer = [Int8](repeating: 0, count: Int(PROC_PIDPATHINFO_SIZE))
    let pathSize = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
    guard pathSize > 0 else { return nil }
    return String(cString: pathBuffer)
}

// MARK: - 私有辅助函数

private func getProcessCommandLine(_ pid: Int32) -> String {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var bufferSize: size_t = 0

    guard sysctl(&mib, u_int(mib.count), nil, &bufferSize, nil, 0) == 0,
          bufferSize > 0 else {
        return ""
    }

    var buffer = [Int8](repeating: 0, count: bufferSize)
    guard sysctl(&mib, u_int(mib.count), &buffer, &bufferSize, nil, 0) == 0,
          bufferSize > MemoryLayout<Int32>.size else {
        return ""
    }

    let argc = buffer.withUnsafeBytes { ptr in
        ptr.load(as: Int32.self)
    }
    guard argc > 0 else { return "" }

    var parts: [String] = []
    var offset = MemoryLayout<Int32>.size

    for _ in 0..<min(Int(argc), 100) {
        guard offset < bufferSize else { break }
        let remaining = buffer.suffix(from: offset)
        guard let nullPos = remaining.firstIndex(of: 0) else { break }

        let segBytes = buffer[offset..<nullPos].map { UInt8(bitPattern: $0) }
        if let str = String(bytes: segBytes, encoding: .utf8), !str.isEmpty {
            parts.append(str)
        }
        offset = nullPos + 1
    }

    guard !parts.isEmpty else { return "" }
    return parts.joined(separator: " ")
}

private func getProcessWorkingDirectory(_ pid: Int32) -> String? {
    var vnodeInfo = proc_vnodepathinfo()
    let size = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnodeInfo, Int32(MemoryLayout<proc_vnodepathinfo>.size))
    guard size > 0 else { return nil }

    let path = withUnsafePointer(to: vnodeInfo.pvi_cdir.vip_path) {
        String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
    }
    guard !path.isEmpty else { return nil }
    return path
}
