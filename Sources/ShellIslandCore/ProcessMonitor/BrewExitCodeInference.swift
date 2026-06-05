import Foundation

extension TaskMonitor {

    // MARK: - Brew Exit Code 推断（从 kitty 输出 / Homebrew 日志推断失败状态）

    func inferExitCodeIfPossible(for task: ObservedTask) -> Int32? {
        guard task.kind == .brew else { return nil }
        guard isBrewInstallCommand(task.commandLine) else { return nil }
        return inferBrewInstallExitCode(task: task)
    }

    func isBrewInstallCommand(_ cmd: String) -> Bool {
        let lower = cmd.lowercased()
        return lower.contains("brew") && lower.contains("install")
    }

    func inferBrewInstallExitCode(task: ObservedTask) -> Int32? {
        // Heuristic: Homebrew writes logs under ~/Library/Logs/Homebrew.
        // If we find a log modified after the task started that contains "Error:",
        // treat it as a failure.
        //
        // Some failures only show up in the terminal output (or the log file isn't discoverable),
        // so we also try to inspect the kitty tab text when available.
        // If we can't prove failure, return nil (keep existing behavior).
        let fm = FileManager.default
        let logsRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Logs")
            .appendingPathComponent("Homebrew")

        let since = task.startedAt.addingTimeInterval(-2)

        guard let enumerator = fm.enumerator(
            at: logsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newestURL: URL?
        var newestDate: Date = since

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]) else { continue }
            guard values.isRegularFile == true else { continue }
            guard let m = values.contentModificationDate else { continue }
            guard m >= since else { continue }
            if m > newestDate {
                newestDate = m
                newestURL = url
            }
        }

        if let logURL = newestURL,
           let data = try? Data(contentsOf: logURL) {
            let text = String(data: data.suffix(48_000), encoding: .utf8) ?? ""
            if text.localizedCaseInsensitiveContains("Error:") || text.localizedCaseInsensitiveContains("ERROR:") {
                logger.warning("推断 brew install 失败（log: \(logURL.lastPathComponent)）")
                return 1
            }
        }

        // Fallback: inspect recent kitty tab output (best-effort).
        return inferBrewFailureFromKittyText(task: task)
    }

    func inferBrewFailureFromKittyText(task: ObservedTask) -> Int32? {
        guard setupState.kittyRemoteControlReady else { return nil }
        guard let ref = task.sessionRef else { return nil }
        guard ref.kittyLeafWindowId != 0 else { return nil }

        guard let raw = kittyIntegration.getTextAll(
            leafWindowId: Int(ref.kittyLeafWindowId),
            socket: ref.kittySocketAddress
        ) else { return nil }

        // Only inspect the tail to avoid scanning huge buffers.
        let tail = String(raw.suffix(48_000))
        let t = tail.lowercased()

        // Homebrew / curl / download failures commonly include these markers.
        let failureMarkers = [
            "error:",
            "failed to download",
            "download failed",
            "requested url returned error",
            "curl:",
            "fatal:",
        ]

        if failureMarkers.contains(where: { t.contains($0) }) {
            logger.warning("推断 brew install 失败（kitty output）")
            return 1
        }

        return nil
    }
}
