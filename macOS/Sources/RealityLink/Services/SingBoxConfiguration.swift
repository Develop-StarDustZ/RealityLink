import Foundation

enum ConfigurationError: LocalizedError {
    case invalidProfile(String)
    case invalidPort
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let message): message
        case .invalidPort: "本地代理端口必须在 1024 到 65535 之间"
        case .serializationFailed: "无法生成 sing-box 配置"
        }
    }
}

enum SingBoxConfiguration {
    static func make(profile: VLESSProfile, settings: AppSettings) throws -> Data {
        if let message = profile.validationMessage {
            throw ConfigurationError.invalidProfile(message)
        }
        guard (1_024...65_535).contains(settings.localPort) else {
            throw ConfigurationError.invalidPort
        }

        let tls = makeTLS(profile)

        var outbound: [String: Any]
        switch profile.proxyProtocol {
        case .vless:
            outbound = [
                "type": "vless", "tag": "proxy", "server": profile.server,
                "server_port": profile.port, "uuid": profile.uuid, "tls": tls
            ]
            if !profile.flow.isEmpty { outbound["flow"] = profile.flow }
        case .vmess:
            outbound = [
                "type": "vmess", "tag": "proxy", "server": profile.server,
                "server_port": profile.port, "uuid": profile.uuid,
                "security": profile.encryption, "alter_id": profile.alterID
            ]
            if profile.security == .tls { outbound["tls"] = tls }
        case .trojan:
            outbound = [
                "type": "trojan", "tag": "proxy", "server": profile.server,
                "server_port": profile.port, "password": profile.password, "tls": tls
            ]
        case .shadowsocks:
            outbound = [
                "type": "shadowsocks", "tag": "proxy", "server": profile.server,
                "server_port": profile.port, "method": profile.encryption, "password": profile.password
            ]
        case .hysteria2:
            outbound = [
                "type": "hysteria2", "tag": "proxy", "server": profile.server,
                "server_port": profile.port, "password": profile.password, "tls": tls
            ]
            if !profile.obfuscation.isEmpty {
                outbound["obfs"] = ["type": profile.obfuscation, "password": profile.obfuscationPassword]
            }
        case .tuic:
            outbound = [
                "type": "tuic", "tag": "proxy", "server": profile.server,
                "server_port": profile.port, "uuid": profile.uuid, "password": profile.password,
                "congestion_control": profile.congestionControl,
                "udp_relay_mode": profile.udpRelayMode,
                "tls": tls
            ]
        }

        if [.vless, .vmess, .trojan].contains(profile.proxyProtocol),
           let transport = makeTransport(profile) {
            outbound["transport"] = transport
        }

        let inbound: [String: Any]
        switch settings.connectionMode {
        case .systemProxy:
            inbound = [
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "127.0.0.1",
                "listen_port": settings.localPort,
                "set_system_proxy": false
            ]
        case .tun:
            inbound = [
                "type": "tun",
                "tag": "tun-in",
                "address": ["172.19.0.1/30"],
                "mtu": 9_000,
                "auto_route": true,
                "strict_route": true,
                "stack": "system"
            ]
        }

        let root: [String: Any] = [
            "log": [
                "level": "info",
                "timestamp": true
            ],
            "inbounds": [inbound],
            "outbounds": [
                outbound,
                ["type": "direct", "tag": "direct"]
            ],
            "route": [
                "auto_detect_interface": true,
                "final": "proxy"
            ]
        ]

        guard JSONSerialization.isValidJSONObject(root) else {
            throw ConfigurationError.serializationFailed
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private static func makeTLS(_ profile: VLESSProfile) -> [String: Any] {
        var tls: [String: Any] = [
            "enabled": true,
            "server_name": profile.serverName,
            "insecure": profile.allowInsecure,
            "utls": ["enabled": true, "fingerprint": profile.fingerprint]
        ]
        let alpn = profile.alpn.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !alpn.isEmpty { tls["alpn"] = alpn }
        if profile.proxyProtocol == .vless && profile.security == .reality {
            tls["reality"] = [
                "enabled": true,
                "public_key": profile.publicKey,
                "short_id": profile.shortID
            ]
        }
        return tls
    }

    private static func makeTransport(_ profile: VLESSProfile) -> [String: Any]? {
        switch profile.transport {
        case .tcp:
            return nil
        case .webSocket:
            var value: [String: Any] = [
                "type": "ws",
                "path": profile.transportPath.isEmpty ? "/" : profile.transportPath
            ]
            if !profile.transportHost.isEmpty {
                value["headers"] = ["Host": profile.transportHost]
            }
            return value
        case .grpc:
            return [
                "type": "grpc",
                "service_name": profile.serviceName
            ]
        case .http2:
            var value: [String: Any] = [
                "type": "http",
                "path": profile.transportPath.isEmpty ? "/" : profile.transportPath
            ]
            let hosts = profile.transportHost.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !hosts.isEmpty { value["host"] = hosts }
            return value
        }
    }
}
