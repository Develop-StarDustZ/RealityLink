import Foundation

struct ProxyEndpoint: Codable, Equatable {
    let enabled: Bool
    let server: String
    let port: Int
    let authenticated: Bool

    static func parse(_ output: String) -> ProxyEndpoint? {
        var fields: [String: String] = [:]
        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        guard let enabledText = fields["Enabled"],
              let portText = fields["Port"],
              let port = Int(portText) else { return nil }
        return ProxyEndpoint(
            enabled: enabledText.lowercased() == "yes",
            server: fields["Server"] ?? "",
            port: port,
            authenticated: fields["Authenticated Proxy Enabled"] == "1"
        )
    }
}

private struct NetworkServiceProxySnapshot: Codable {
    let service: String
    let web: ProxyEndpoint
    let secureWeb: ProxyEndpoint
    let socks: ProxyEndpoint
}

private struct SystemProxySnapshot: Codable {
    let services: [NetworkServiceProxySnapshot]
    let localPort: Int
}

@MainActor
final class SystemProxyManager {
    private let fileManager = FileManager.default
    private var snapshotURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("RealityLink", isDirectory: true)
            .appendingPathComponent("system-proxy-backup.json")
    }

    var hasSnapshot: Bool {
        fileManager.fileExists(atPath: snapshotURL.path)
    }

    func enable(port: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            guard !hasSnapshot else { throw ProxyManagerError.pendingRestore }
            let services = try listNetworkServices()
            guard !services.isEmpty else { throw ProxyManagerError.noNetworkServices }

            let snapshots = try services.map { service in
                NetworkServiceProxySnapshot(
                    service: service,
                    web: try readProxy(service: service, kind: .web),
                    secureWeb: try readProxy(service: service, kind: .secureWeb),
                    socks: try readProxy(service: service, kind: .socks)
                )
            }
            if snapshots.contains(where: { $0.web.authenticated || $0.secureWeb.authenticated || $0.socks.authenticated }) {
                throw ProxyManagerError.authenticatedProxyUnsupported
            }

            try save(SystemProxySnapshot(services: snapshots, localPort: port))
            let command = makeEnableCommand(services: services, port: port)
            runWithAuthorizationFallback(command: command) { [weak self] result in
                guard let self else { return }
                if case .failure = result, !self.currentProxyUsesManagedPort(port, services: services) {
                    try? self.fileManager.removeItem(at: self.snapshotURL)
                }
                completion(result)
            }
        } catch {
            completion(.failure(error))
        }
    }

    func restore(completion: @escaping (Result<Void, Error>) -> Void) {
        do {
            guard hasSnapshot else {
                completion(.success(()))
                return
            }
            let data = try Data(contentsOf: snapshotURL)
            let snapshot = try JSONDecoder().decode(SystemProxySnapshot.self, from: data)
            let command = makeRestoreCommand(snapshot: snapshot)
            runWithAuthorizationFallback(command: command) { [weak self] result in
                if case .success = result, let self {
                    try? self.fileManager.removeItem(at: self.snapshotURL)
                }
                completion(result)
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func listNetworkServices() throws -> [String] {
        let output = try runAndCapture(
            executable: "/usr/sbin/networksetup",
            arguments: ["-listallnetworkservices"]
        )
        return output
            .split(whereSeparator: \Character.isNewline)
            .dropFirst()
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
    }

    private func readProxy(service: String, kind: ProxyKind) throws -> ProxyEndpoint {
        let output = try runAndCapture(
            executable: "/usr/sbin/networksetup",
            arguments: [kind.getArgument, service]
        )
        guard let endpoint = ProxyEndpoint.parse(output) else {
            throw ProxyManagerError.cannotReadService(service)
        }
        return endpoint
    }

    private func save(_ snapshot: SystemProxySnapshot) throws {
        try fileManager.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
    }

    private func makeEnableCommand(services: [String], port: Int) -> String {
        var commands = ["set -e"]
        for service in services {
            let name = shellQuote(service)
            commands += [
                "/usr/sbin/networksetup -setwebproxy \(name) 127.0.0.1 \(port)",
                "/usr/sbin/networksetup -setwebproxystate \(name) on",
                "/usr/sbin/networksetup -setsecurewebproxy \(name) 127.0.0.1 \(port)",
                "/usr/sbin/networksetup -setsecurewebproxystate \(name) on",
                "/usr/sbin/networksetup -setsocksfirewallproxy \(name) 127.0.0.1 \(port)",
                "/usr/sbin/networksetup -setsocksfirewallproxystate \(name) on"
            ]
        }
        return commands.joined(separator: "; ")
    }

    private func makeRestoreCommand(snapshot: SystemProxySnapshot) -> String {
        var commands = ["set -e"]
        for service in snapshot.services {
            let name = shellQuote(service.service)
            commands += restoreCommands(kind: .web, endpoint: service.web, service: name)
            commands += restoreCommands(kind: .secureWeb, endpoint: service.secureWeb, service: name)
            commands += restoreCommands(kind: .socks, endpoint: service.socks, service: name)
        }
        return commands.joined(separator: "; ")
    }

    private func restoreCommands(kind: ProxyKind, endpoint: ProxyEndpoint, service: String) -> [String] {
        var commands: [String] = []
        if !endpoint.server.isEmpty, endpoint.port > 0 {
            commands.append(
                "/usr/sbin/networksetup \(kind.setArgument) \(service) \(shellQuote(endpoint.server)) \(endpoint.port)"
            )
        }
        commands.append(
            "/usr/sbin/networksetup \(kind.stateArgument) \(service) \(endpoint.enabled ? "on" : "off")"
        )
        return commands
    }

    private func runWithAuthorizationFallback(
        command: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        runAsync(executable: "/bin/sh", arguments: ["-c", command]) { [weak self] firstResult in
            switch firstResult {
            case .success:
                completion(.success(()))
            case .failure:
                guard let self else { return }
                let script = "do shell script \"\(self.appleScriptEscape(command))\" with administrator privileges"
                self.runAsync(executable: "/usr/bin/osascript", arguments: ["-e", script], completion: completion)
            }
        }
    }

    private func runAsync(
        executable: String,
        arguments: [String],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { process in
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(ProxyManagerError.commandFailed(
                        output.isEmpty ? "系统网络设置命令失败（状态码 \(process.terminationStatus)）" : output
                    )))
                }
            }
        }
        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }

    private func runAndCapture(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ProxyManagerError.commandFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    private func currentProxyUsesManagedPort(_ port: Int, services: [String]) -> Bool {
        services.contains { service in
            ProxyKind.allCases.contains { kind in
                guard let endpoint = try? readProxy(service: service, kind: kind) else { return false }
                return endpoint.enabled && endpoint.server == "127.0.0.1" && endpoint.port == port
            }
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private enum ProxyKind: CaseIterable {
        case web
        case secureWeb
        case socks

        var getArgument: String {
            switch self {
            case .web: "-getwebproxy"
            case .secureWeb: "-getsecurewebproxy"
            case .socks: "-getsocksfirewallproxy"
            }
        }

        var setArgument: String {
            switch self {
            case .web: "-setwebproxy"
            case .secureWeb: "-setsecurewebproxy"
            case .socks: "-setsocksfirewallproxy"
            }
        }

        var stateArgument: String {
            switch self {
            case .web: "-setwebproxystate"
            case .secureWeb: "-setsecurewebproxystate"
            case .socks: "-setsocksfirewallproxystate"
            }
        }
    }
}

private enum ProxyManagerError: LocalizedError {
    case pendingRestore
    case noNetworkServices
    case cannotReadService(String)
    case authenticatedProxyUnsupported
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .pendingRestore:
            return "检测到尚未恢复的系统代理备份，请重新打开 App 完成恢复"
        case .noNetworkServices:
            return "没有找到可用的 macOS 网络服务"
        case .cannotReadService(let service):
            return "无法读取网络服务“\(service)”的代理配置"
        case .authenticatedProxyUnsupported:
            return "当前系统已配置带密码的代理。为避免丢失凭据，请改用全局 TUN 模式。"
        case .commandFailed(let message):
            return message
        }
    }
}
