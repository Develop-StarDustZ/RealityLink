import Darwin
import Foundation

@MainActor
final class SingBoxService: ObservableObject {
    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var logs: [String] = []
    @Published private(set) var connectedProfileName: String?
    @Published private(set) var connectedProfileID: UUID?

    private var coreProcess: Process?
    private var outputPipe: Pipe?
    private var tunTimer: Timer?
    private var tunPID: pid_t?
    private var tunLogOffset: UInt64 = 0
    private var activeMode: ConnectionMode?
    private var expectedStop = false
    private var restoringSystemProxy = false
    private var systemSwitchRestartPending = false
    private var pendingProfile: VLESSProfile?
    private var pendingCoreURL: URL?
    private var tunSwitchCandidatePID: pid_t?
    private let proxyManager = SystemProxyManager()

    private let fileManager = FileManager.default
    private lazy var runtimeDirectory: URL = {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("RealityLink", isDirectory: true)
    }()
    private var configURL: URL { runtimeDirectory.appendingPathComponent("runtime.json") }
    private var tunPIDURL: URL { runtimeDirectory.appendingPathComponent("tun.pid") }
    private var tunLogURL: URL { runtimeDirectory.appendingPathComponent("tun.log") }
    private var tunStopURL: URL { runtimeDirectory.appendingPathComponent("tun.stop") }
    private var tunReloadURL: URL { runtimeDirectory.appendingPathComponent("tun.reload") }
    private var nextConfigURL: URL { runtimeDirectory.appendingPathComponent("runtime-next.json") }

    func start(profile: VLESSProfile, settings: AppSettings) {
        guard state == .disconnected || isFailed else { return }
        state = .connecting
        logs = []
        connectedProfileName = profile.name
        connectedProfileID = profile.id
        activeMode = settings.connectionMode
        expectedStop = false

        do {
            let coreURL = try locateCore(customPath: settings.corePath)
            let configuration = try SingBoxConfiguration.make(profile: profile, settings: settings)
            try prepareRuntime(configuration: configuration)
            try validateConfiguration(coreURL: coreURL)
            appendLog("配置检查通过，内核：\(coreURL.path)")

            switch settings.connectionMode {
            case .systemProxy:
                try startSystemProxy(coreURL: coreURL, localPort: settings.localPort)
            case .tun:
                try startTUN(coreURL: coreURL)
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    func switchProfile(to profile: VLESSProfile, settings: AppSettings) {
        guard state == .connected, profile.id != connectedProfileID else { return }
        guard settings.connectionMode == activeMode else {
            appendLog("切换失败：连接模式在连接期间不可更改")
            return
        }

        do {
            let coreURL = try locateCore(customPath: settings.corePath)
            let configuration = try SingBoxConfiguration.make(profile: profile, settings: settings)
            try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
            try configuration.write(to: nextConfigURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: nextConfigURL.path)
            defer { try? fileManager.removeItem(at: nextConfigURL) }
            try validateConfiguration(coreURL: coreURL, configURL: nextConfigURL)

            try configuration.write(to: configURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            pendingProfile = profile
            pendingCoreURL = coreURL
            state = .switching
            appendLog("新节点配置检查通过，正在切换到 \(profile.name)…")

            switch activeMode {
            case .systemProxy:
                systemSwitchRestartPending = true
                coreProcess?.terminate()
            case .tun:
                tunSwitchCandidatePID = nil
                try? fileManager.removeItem(at: tunReloadURL)
                try Data("reload\n".utf8).write(to: tunReloadURL, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tunReloadURL.path)
                appendLog("已通知已授权的 TUN 控制进程切换节点，无需再次输入密码")
            case .none:
                throw ServiceError.noActiveConnection
            }
        } catch {
            pendingProfile = nil
            pendingCoreURL = nil
            systemSwitchRestartPending = false
            if state == .switching { state = .connected }
            appendLog("切换失败：\(error.localizedDescription)")
        }
    }

    func stop() {
        guard state.isConnected || state == .connecting else { return }
        state = .disconnecting
        expectedStop = true

        switch activeMode {
        case .systemProxy:
            appendLog("正在停止内核并恢复系统代理…")
            restoringSystemProxy = true
            proxyManager.restore { [weak self] result in
                guard let self else { return }
                self.restoringSystemProxy = false
                switch result {
                case .success:
                    self.appendLog("原系统代理设置已恢复")
                    self.coreProcess?.terminate()
                    if self.coreProcess?.isRunning != true {
                        self.finishStop()
                    }
                case .failure(let error):
                    self.expectedStop = false
                    if self.coreProcess?.isRunning == true {
                        self.state = .connected
                        self.appendLog("恢复系统代理失败：\(error.localizedDescription)")
                    } else {
                        self.fail("内核已停止，但系统代理恢复失败：\(error.localizedDescription)")
                    }
                }
            }
        case .tun:
            if tunPID == nil {
                coreProcess?.terminate()
                finishStop()
            } else {
                stopTUN()
            }
        case .none:
            finishStop()
        }
    }

    func clearLogs() {
        logs = []
    }

    func recoverNetworkStateIfNeeded() {
        guard state == .disconnected else { return }
        if let text = try? String(contentsOf: tunPIDURL, encoding: .utf8),
           let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
           processIsAlive(value),
           isManagedTUNProcess(value) {
            tunPID = value
            activeMode = .tun
            connectedProfileName = "上次 TUN 会话"
            connectedProfileID = nil
            tunLogOffset = 0
            readTUNLog()
            appendLog("检测到仍在运行的 TUN 内核，已恢复控制")
            state = .connected
            startTUNTimer()
            return
        }

        guard proxyManager.hasSnapshot else { return }
        state = .disconnecting
        restoringSystemProxy = true
        appendLog("检测到上次运行遗留的系统代理，正在恢复…")
        proxyManager.restore { [weak self] result in
            guard let self else { return }
            self.restoringSystemProxy = false
            switch result {
            case .success:
                self.appendLog("原系统代理设置已恢复")
                self.finishStop()
            case .failure(let error):
                self.fail("自动恢复系统代理失败：\(error.localizedDescription)")
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private func locateCore(customPath: String) throws -> URL {
        let candidates: [String] = [
            customPath.trimmingCharacters(in: .whitespacesAndNewlines),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/sing-box").path,
            "/opt/homebrew/bin/sing-box",
            "/usr/local/bin/sing-box"
        ].filter { !$0.isEmpty }

        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw ServiceError.coreNotFound
    }

    private func prepareRuntime(configuration: Data) throws {
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try configuration.write(to: configURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func validateConfiguration(coreURL: URL, configURL: URL? = nil) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = coreURL
        process.arguments = ["check", "-c", (configURL ?? self.configURL).path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw ServiceError.configurationRejected(output.isEmpty ? "sing-box 拒绝了配置" : output)
        }
    }

    private func startSystemProxy(coreURL: URL, localPort: Int) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = coreURL
        process.arguments = ["run", "-c", configURL.path]
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleCoreTermination(status: process.terminationStatus)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(text)
            }
        }

        try process.run()
        coreProcess = process
        outputPipe = pipe

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self, weak process] in
            guard let self, self.state == .connecting else { return }
            if process?.isRunning == true {
                self.appendLog("内核已启动，正在设置 macOS 系统代理…")
                self.proxyManager.enable(port: localPort) { [weak self, weak process] result in
                    guard let self, self.state == .connecting else { return }
                    switch result {
                    case .success:
                        guard process?.isRunning == true else {
                            self.fail("设置系统代理期间 sing-box 已退出")
                            return
                        }
                        self.state = .connected
                        self.appendLog("macOS HTTP、HTTPS 和 SOCKS5 系统代理已启用")
                    case .failure(let error):
                        self.abortSystemProxyStart(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func abortSystemProxyStart(message: String) {
        coreProcess?.terminationHandler = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        coreProcess?.terminate()
        coreProcess = nil
        outputPipe = nil
        activeMode = nil
        fail("无法设置系统代理：\(message)")
    }

    private func startSystemProxyAfterSwitch(coreURL: URL) throws {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = coreURL
        process.arguments = ["run", "-c", configURL.path]
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleCoreTermination(status: process.terminationStatus)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.appendOutput(text) }
        }
        try process.run()
        coreProcess = process
        outputPipe = pipe

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak process] in
            guard let self, self.state == .switching else { return }
            guard process?.isRunning == true else { return }
            self.completeProfileSwitch()
        }
    }

    private func startTUN(coreURL: URL) throws {
        try? fileManager.removeItem(at: tunPIDURL)
        try? fileManager.removeItem(at: tunLogURL)
        try? fileManager.removeItem(at: tunStopURL)
        try? fileManager.removeItem(at: tunReloadURL)
        try Data().write(to: tunPIDURL, options: .atomic)
        try Data().write(to: tunLogURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tunPIDURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tunLogURL.path)
        tunLogOffset = 0

        let shellCommand = TUNCommandBuilder.startCommand(
            corePath: coreURL.path,
            configPath: configURL.path,
            logPath: tunLogURL.path,
            pidPath: tunPIDURL.path,
            stopPath: tunStopURL.path,
            reloadPath: tunReloadURL.path
        )

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(appleScriptEscape(shellCommand))\" with administrator privileges"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                self.handleTUNWrapperTermination(status: process.terminationStatus, output: output)
            }
        }
        try process.run()
        coreProcess = process
        outputPipe = pipe
        appendLog("正在请求管理员授权以创建 TUN 接口…")
        waitForTUNStartup()
    }

    private func waitForTUNStartup() {
        guard state == .connecting else { return }
        if let text = try? String(contentsOf: tunPIDURL, encoding: .utf8),
           Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil {
            beginTUNMonitoring()
            return
        }
        guard coreProcess?.isRunning == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.waitForTUNStartup()
        }
    }

    private func beginTUNMonitoring() {
        guard state == .connecting else { return }
        guard let text = try? String(contentsOf: tunPIDURL, encoding: .utf8),
              let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            fail("未能读取 TUN 内核进程号")
            return
        }

        tunPID = value
        readTUNLog()
        guard processIsAlive(value) else {
            fail(lastLogLine ?? "TUN 内核启动后立即退出")
            return
        }

        state = .connected
        appendLog("全局 TUN 已启用")
        startTUNTimer()
    }

    private func startTUNTimer() {
        tunTimer?.invalidate()
        tunTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pollTUN()
            }
        }
    }

    private func pollTUN() {
        readTUNLog()
        if state == .switching {
            pollTUNSwitch()
            return
        }
        guard let tunPID, processIsAlive(tunPID) else {
            tunTimer?.invalidate()
            tunTimer = nil
            if expectedStop {
                finishStop()
            } else {
                fail(lastLogLine ?? "TUN 内核意外退出")
            }
            return
        }
    }

    private func pollTUNSwitch() {
        guard coreProcess?.isRunning == true else { return }
        guard let text = try? String(contentsOf: tunPIDURL, encoding: .utf8),
              let newPID = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              newPID != tunPID,
              processIsAlive(newPID) else { return }

        if tunSwitchCandidatePID == newPID {
            tunPID = newPID
            tunSwitchCandidatePID = nil
            completeProfileSwitch()
        } else {
            tunSwitchCandidatePID = newPID
        }
    }

    private func completeProfileSwitch() {
        guard let profile = pendingProfile else { return }
        connectedProfileID = profile.id
        connectedProfileName = profile.name
        pendingProfile = nil
        pendingCoreURL = nil
        systemSwitchRestartPending = false
        state = .connected
        appendLog("已切换到 \(profile.name)")
    }

    private func stopTUN() {
        guard let tunPID else {
            finishStop()
            return
        }

        do {
            try Data("stop\n".utf8).write(to: tunStopURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tunStopURL.path)
            appendLog("已发送 TUN 停止信号，无需再次输入管理员密码")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self,
                      self.state == .disconnecting,
                      self.processIsAlive(tunPID) else { return }
                self.appendLog("受限控制进程未响应，正在使用管理员授权兜底停止…")
                self.stopTUNWithAuthorization(pid: tunPID)
            }
        } catch {
            appendLog("写入停止信号失败，正在使用管理员授权兜底停止…")
            stopTUNWithAuthorization(pid: tunPID)
        }
    }

    private func stopTUNWithAuthorization(pid tunPID: pid_t) {

        let shellCommand = "/bin/kill -TERM \(tunPID)"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "do shell script \"\(appleScriptEscape(shellCommand))\" with administrator privileges"]
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { [weak self] process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                if process.terminationStatus == 0 {
                    self.appendLog("TUN 内核已停止")
                    self.finishStop()
                } else {
                    self.expectedStop = false
                    self.state = .connected
                    self.appendLog("断开失败：\(output.isEmpty ? "需要管理员授权" : output)")
                }
            }
        }
        do {
            try process.run()
            coreProcess = process
            outputPipe = pipe
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func handleTUNWrapperTermination(status: Int32, output: String) {
        readTUNLog()
        coreProcess = nil
        outputPipe = nil
        guard state != .disconnected, !isFailed else { return }

        if expectedStop || state == .disconnecting {
            finishStop()
        } else if state == .connecting {
            fail(output.isEmpty ? (lastLogLine ?? "管理员授权已取消") : output)
        } else {
            fail(lastLogLine ?? "TUN 控制进程已退出（状态码 \(status)）")
        }
    }

    private func readTUNLog() {
        guard let handle = try? FileHandle(forReadingFrom: tunLogURL) else { return }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            if size < tunLogOffset { tunLogOffset = 0 }
            try handle.seek(toOffset: tunLogOffset)
            let data = handle.readDataToEndOfFile()
            tunLogOffset = size
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                appendOutput(text)
            }
        } catch {
            appendLog("读取日志失败：\(error.localizedDescription)")
        }
    }

    private func processIsAlive(_ pid: pid_t) -> Bool {
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func isManagedTUNProcess(_ pid: pid_t) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "command="]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let command = String(data: data, encoding: .utf8) ?? ""
            return process.terminationStatus == 0
                && command.contains("sing-box")
                && command.contains(configURL.path)
        } catch {
            return false
        }
    }

    private func handleCoreTermination(status: Int32) {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        coreProcess = nil
        outputPipe = nil

        if restoringSystemProxy {
            return
        }
        if state == .switching, activeMode == .systemProxy, systemSwitchRestartPending,
           let coreURL = pendingCoreURL {
            systemSwitchRestartPending = false
            appendLog("旧节点内核已停止，正在启动新节点…")
            do {
                try startSystemProxyAfterSwitch(coreURL: coreURL)
            } catch {
                restoreSystemProxyAfterSwitchFailure("无法启动新节点：\(error.localizedDescription)")
            }
            return
        }
        if expectedStop || state == .disconnecting {
            finishStop()
        } else if activeMode == .systemProxy, proxyManager.hasSnapshot {
            restoringSystemProxy = true
            state = .disconnecting
            appendLog("sing-box 意外退出，正在恢复系统代理…")
            proxyManager.restore { [weak self] result in
                guard let self else { return }
                self.restoringSystemProxy = false
                switch result {
                case .success:
                    self.fail("sing-box 已退出（状态码 \(status)），系统代理已恢复")
                case .failure(let error):
                    self.fail("sing-box 已退出，且系统代理恢复失败：\(error.localizedDescription)")
                }
            }
        } else {
            fail("sing-box 已退出（状态码 \(status)）")
        }
    }

    private func restoreSystemProxyAfterSwitchFailure(_ message: String) {
        restoringSystemProxy = true
        state = .disconnecting
        proxyManager.restore { [weak self] result in
            guard let self else { return }
            self.restoringSystemProxy = false
            switch result {
            case .success:
                self.fail("\(message)，系统代理已恢复")
            case .failure(let error):
                self.fail("\(message)，且系统代理恢复失败：\(error.localizedDescription)")
            }
        }
    }

    private func finishStop() {
        tunTimer?.invalidate()
        tunTimer = nil
        tunPID = nil
        coreProcess = nil
        outputPipe = nil
        activeMode = nil
        expectedStop = false
        restoringSystemProxy = false
        systemSwitchRestartPending = false
        pendingProfile = nil
        pendingCoreURL = nil
        tunSwitchCandidatePID = nil
        try? fileManager.removeItem(at: tunStopURL)
        try? fileManager.removeItem(at: tunReloadURL)
        try? fileManager.removeItem(at: tunPIDURL)
        connectedProfileName = nil
        connectedProfileID = nil
        state = .disconnected
    }

    private func fail(_ message: String) {
        appendLog("错误：\(message)")
        tunTimer?.invalidate()
        tunTimer = nil
        tunPID = nil
        coreProcess = nil
        outputPipe = nil
        activeMode = nil
        expectedStop = false
        restoringSystemProxy = false
        systemSwitchRestartPending = false
        pendingProfile = nil
        pendingCoreURL = nil
        tunSwitchCandidatePID = nil
        connectedProfileName = nil
        connectedProfileID = nil
        state = .failed(message)
    }

    private func appendOutput(_ output: String) {
        output.split(whereSeparator: \Character.isNewline).forEach { line in
            appendLog(String(line))
        }
    }

    private func appendLog(_ line: String) {
        logs.append(line)
        if logs.count > 1_000 {
            logs.removeFirst(logs.count - 1_000)
        }
    }

    private var lastLogLine: String? {
        logs.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private enum ServiceError: LocalizedError {
    case coreNotFound
    case configurationRejected(String)
    case noActiveConnection

    var errorDescription: String? {
        switch self {
        case .coreNotFound:
            return "找不到 sing-box。请先运行 brew install sing-box，或在设置中指定路径。"
        case .configurationRejected(let message):
            return "配置检查失败：\(message)"
        case .noActiveConnection:
            return "当前没有可切换的连接"
        }
    }
}
