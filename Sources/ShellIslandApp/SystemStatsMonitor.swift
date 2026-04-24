import Foundation
import Darwin

struct SystemStats: Equatable, Sendable {
    var cpuLoadPercent: Int
    var memoryUsedPercent: Int
    var uptimeHours: Int

    static let zero = SystemStats(cpuLoadPercent: 0, memoryUsedPercent: 0, uptimeHours: 0)
}

@MainActor
final class SystemStatsMonitor: NSObject, ObservableObject {
    @Published private(set) var stats = SystemStats.zero

    private var timer: Timer?
    private var previousCPUTicks: host_cpu_load_info_data_t?

    func start() {
        guard timer == nil else { return }
        refresh()

        let timer = Timer.scheduledTimer(
            timeInterval: 2.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        stats = SystemStats(
            cpuLoadPercent: readCPULoad(),
            memoryUsedPercent: readMemoryUsage(),
            uptimeHours: Int(ProcessInfo.processInfo.systemUptime / 3600)
        )
    }

    @objc private func timerFired() {
        refresh()
    }

    private func readCPULoad() -> Int {
        var cpuInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &cpuInfo) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return stats.cpuLoadPercent }

        defer { previousCPUTicks = cpuInfo }

        guard let previousCPUTicks else {
            return stats.cpuLoadPercent
        }

        let user = Double(cpuInfo.cpu_ticks.0 - previousCPUTicks.cpu_ticks.0)
        let system = Double(cpuInfo.cpu_ticks.1 - previousCPUTicks.cpu_ticks.1)
        let idle = Double(cpuInfo.cpu_ticks.2 - previousCPUTicks.cpu_ticks.2)
        let nice = Double(cpuInfo.cpu_ticks.3 - previousCPUTicks.cpu_ticks.3)
        let total = user + system + idle + nice

        guard total > 0 else { return stats.cpuLoadPercent }
        let busy = user + system + nice
        return max(0, min(100, Int((busy / total) * 100)))
    }

    private func readMemoryUsage() -> Int {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats64 = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &stats64) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return stats.memoryUsedPercent }

        let pageSize = UInt64(vm_kernel_page_size)
        let usedPages =
            UInt64(stats64.active_count) +
            UInt64(stats64.wire_count) +
            UInt64(stats64.compressor_page_count)
        let usedBytes = usedPages * pageSize
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        guard totalBytes > 0 else { return stats.memoryUsedPercent }
        return max(0, min(100, Int((Double(usedBytes) / Double(totalBytes)) * 100)))
    }
}
