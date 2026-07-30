import Foundation

enum ProxyProtocol: String, Codable, CaseIterable, Identifiable {
    case vless
    case vmess
    case trojan
    case shadowsocks
    case hysteria2
    case tuic

    var id: String { rawValue }
}

enum VLESSSecurity: String, Codable, CaseIterable, Identifiable {
    case none
    case reality
    case tls

    var id: String { rawValue }
}

enum VLESSTransport: String, Codable, CaseIterable, Identifiable {
    case tcp
    case webSocket = "ws"
    case grpc
    case http2 = "http"

    var id: String { rawValue }
}

struct VLESSProfile: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var server: String
    var port: Int
    var uuid: String
    var serverName: String
    var publicKey: String
    var shortID: String
    var fingerprint: String
    var flow: String
    var proxyProtocol: ProxyProtocol
    var password: String
    var encryption: String
    var alterID: Int
    var obfuscation: String
    var obfuscationPassword: String
    var congestionControl: String
    var udpRelayMode: String
    var security: VLESSSecurity
    var transport: VLESSTransport
    var transportPath: String
    var transportHost: String
    var serviceName: String
    var allowInsecure: Bool
    var alpn: String
    var subscriptionID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "新节点",
        server: String = "",
        port: Int = 443,
        uuid: String = "",
        serverName: String = "",
        publicKey: String = "",
        shortID: String = "",
        fingerprint: String = "chrome",
        flow: String = "xtls-rprx-vision",
        proxyProtocol: ProxyProtocol = .vless,
        password: String = "",
        encryption: String = "auto",
        alterID: Int = 0,
        obfuscation: String = "",
        obfuscationPassword: String = "",
        congestionControl: String = "cubic",
        udpRelayMode: String = "native",
        security: VLESSSecurity = .reality,
        transport: VLESSTransport = .tcp,
        transportPath: String = "",
        transportHost: String = "",
        serviceName: String = "",
        allowInsecure: Bool = false,
        alpn: String = "",
        subscriptionID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.server = server
        self.port = port
        self.uuid = uuid
        self.serverName = serverName
        self.publicKey = publicKey
        self.shortID = shortID
        self.fingerprint = fingerprint
        self.flow = flow
        self.proxyProtocol = proxyProtocol
        self.password = password
        self.encryption = encryption
        self.alterID = alterID
        self.obfuscation = obfuscation
        self.obfuscationPassword = obfuscationPassword
        self.congestionControl = congestionControl
        self.udpRelayMode = udpRelayMode
        self.security = security
        self.transport = transport
        self.transportPath = transportPath
        self.transportHost = transportHost
        self.serviceName = serviceName
        self.allowInsecure = allowInsecure
        self.alpn = alpn
        self.subscriptionID = subscriptionID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, server, port, uuid, serverName, publicKey, shortID, fingerprint, flow
        case proxyProtocol, password, encryption, alterID, obfuscation, obfuscationPassword, congestionControl, udpRelayMode
        case security, transport, transportPath, transportHost, serviceName, allowInsecure, alpn, subscriptionID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        server = try container.decode(String.self, forKey: .server)
        port = try container.decode(Int.self, forKey: .port)
        uuid = try container.decode(String.self, forKey: .uuid)
        serverName = try container.decode(String.self, forKey: .serverName)
        publicKey = try container.decode(String.self, forKey: .publicKey)
        shortID = try container.decode(String.self, forKey: .shortID)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        flow = try container.decode(String.self, forKey: .flow)
        proxyProtocol = try container.decodeIfPresent(ProxyProtocol.self, forKey: .proxyProtocol) ?? .vless
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        encryption = try container.decodeIfPresent(String.self, forKey: .encryption) ?? "auto"
        alterID = try container.decodeIfPresent(Int.self, forKey: .alterID) ?? 0
        obfuscation = try container.decodeIfPresent(String.self, forKey: .obfuscation) ?? ""
        obfuscationPassword = try container.decodeIfPresent(String.self, forKey: .obfuscationPassword) ?? ""
        congestionControl = try container.decodeIfPresent(String.self, forKey: .congestionControl) ?? "cubic"
        udpRelayMode = try container.decodeIfPresent(String.self, forKey: .udpRelayMode) ?? "native"
        security = try container.decodeIfPresent(VLESSSecurity.self, forKey: .security) ?? .reality
        transport = try container.decodeIfPresent(VLESSTransport.self, forKey: .transport) ?? .tcp
        transportPath = try container.decodeIfPresent(String.self, forKey: .transportPath) ?? ""
        transportHost = try container.decodeIfPresent(String.self, forKey: .transportHost) ?? ""
        serviceName = try container.decodeIfPresent(String.self, forKey: .serviceName) ?? ""
        allowInsecure = try container.decodeIfPresent(Bool.self, forKey: .allowInsecure) ?? false
        alpn = try container.decodeIfPresent(String.self, forKey: .alpn) ?? ""
        subscriptionID = try container.decodeIfPresent(UUID.self, forKey: .subscriptionID)
    }

    var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写节点名称"
        }
        if server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写服务器地址"
        }
        if !(1...65_535).contains(port) {
            return "端口必须在 1 到 65535 之间"
        }
        if [.vless, .vmess, .tuic].contains(proxyProtocol), UUID(uuidString: uuid) == nil {
            return "UUID 格式不正确"
        }
        if requiresTLS, serverName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写 TLS SNI"
        }
        if proxyProtocol == .vless && security == .none {
            return "VLESS 当前需要 Reality 或 TLS"
        }
        if proxyProtocol == .vless && security == .reality {
            guard transport == .tcp else { return "Reality 当前仅支持 TCP/raw 传输" }
            let keyCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
            if publicKey.count < 40 || publicKey.unicodeScalars.contains(where: { !keyCharacters.contains($0) }) {
                return "Reality 公钥格式不正确"
            }
            let hexCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
            if shortID.count > 16 || shortID.count % 2 != 0 || shortID.unicodeScalars.contains(where: { !hexCharacters.contains($0) }) {
                return "Short ID 应为不超过 16 位的偶数长度十六进制字符串"
            }
        }
        if [.trojan, .shadowsocks, .hysteria2, .tuic].contains(proxyProtocol), password.isEmpty {
            return "请填写密码"
        }
        if proxyProtocol == .shadowsocks && encryption.isEmpty {
            return "请选择 Shadowsocks 加密方式"
        }
        if proxyProtocol == .hysteria2 && !obfuscation.isEmpty && obfuscation != "salamander" {
            return "sing-box 1.13 仅支持 Hysteria2 salamander 混淆"
        }
        return nil
    }

    var requiresTLS: Bool {
        switch proxyProtocol {
        case .vless, .vmess: security != .none
        case .trojan, .hysteria2, .tuic: true
        case .shadowsocks: false
        }
    }

    static let preview = VLESSProfile(
        name: "示例节点",
        server: "vpn.example.com",
        uuid: "00000000-0000-4000-8000-000000000000",
        serverName: "www.example.com",
        publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        shortID: "0123456789abcdef"
    )
}

enum ConnectionMode: String, Codable, CaseIterable, Identifiable {
    case systemProxy
    case tun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemProxy: "系统代理"
        case .tun: "全局 TUN"
        }
    }

    var detail: String {
        switch self {
        case .systemProxy: "覆盖遵循 macOS 代理设置的应用；受限设备会要求管理员授权"
        case .tun: "接管大多数 TCP/UDP 流量；首次连接授权后，切换和断开无需再次输入密码"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var connectionMode: ConnectionMode = .systemProxy
    var localPort: Int = 20_890
    var corePath: String = ""
}

enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case switching
    case disconnecting
    case failed(String)

    var title: String {
        switch self {
        case .disconnected: "未连接"
        case .connecting: "正在连接"
        case .connected: "已连接"
        case .switching: "正在切换"
        case .disconnecting: "正在断开"
        case .failed: "连接失败"
        }
    }

    var isBusy: Bool {
        self == .connecting || self == .switching || self == .disconnecting
    }

    var isConnected: Bool {
        self == .connected || self == .switching
    }
}
