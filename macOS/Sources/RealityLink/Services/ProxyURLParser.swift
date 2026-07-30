import Foundation

enum ProxyURLParserError: LocalizedError, Equatable {
    case unsupportedScheme
    case invalidLink(String)
    case unsupportedOption(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedScheme:
            return "不支持这个节点协议"
        case .invalidLink(let protocolName):
            return "这不是有效的 \(protocolName) 链接"
        case .unsupportedOption(let option):
            return "当前版本不支持：\(option)"
        }
    }
}

enum ProxyURLParser {
    static func parse(_ text: String) throws -> VLESSProfile {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheme = value.split(separator: ":", maxSplits: 1).first?.lowercased()
        switch scheme {
        case "vless": return try VLESSURLParser.parse(value)
        case "vmess": return try parseVMess(value)
        case "trojan": return try parseTrojan(value)
        case "ss": return try parseShadowsocks(value)
        case "hysteria2", "hy2": return try parseHysteria2(value)
        case "tuic": return try parseTUIC(value)
        default: throw ProxyURLParserError.unsupportedScheme
        }
    }

    private static func parseVMess(_ value: String) throws -> VLESSProfile {
        let payload = sharePayload(value)
        if let data = decodeBase64(payload),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let server = string(object["add"])
            let uuid = string(object["id"])
            guard !server.isEmpty, UUID(uuidString: uuid) != nil else {
                throw ProxyURLParserError.invalidLink("VMess")
            }
            let port = int(object["port"]) ?? 443
            let network = string(object["net"])
            let transport = try parseTransport(network)
            let tlsEnabled = ["tls", "1", "true"].contains(string(object["tls"]).lowercased())
            let path = string(object["path"])
            let host = string(object["host"])
            let profile = VLESSProfile(
                name: nonEmpty(string(object["ps"])) ?? server,
                server: server,
                port: port,
                uuid: uuid,
                serverName: nonEmpty(string(object["sni"])) ?? (tlsEnabled ? server : ""),
                fingerprint: nonEmpty(string(object["fp"])) ?? "chrome",
                flow: "",
                proxyProtocol: .vmess,
                encryption: nonEmpty(string(object["scy"])) ?? "auto",
                alterID: int(object["aid"]) ?? 0,
                security: tlsEnabled ? .tls : .none,
                transport: transport,
                transportPath: transport == .grpc ? "" : path,
                transportHost: host,
                serviceName: transport == .grpc ? (nonEmpty(path) ?? string(object["serviceName"])) : "",
                allowInsecure: bool(object["allowInsecure"]),
                alpn: string(object["alpn"])
            )
            return try validated(profile)
        }

        guard let components = URLComponents(string: value),
              let host = components.host,
              let uuid = components.user,
              UUID(uuidString: uuid) != nil else {
            throw ProxyURLParserError.invalidLink("VMess")
        }
        let query = queryMap(components)
        let transport = try parseTransport(query["type"])
        let tlsEnabled = query["security"]?.lowercased() == "tls"
        let profile = VLESSProfile(
            name: decodedName(components) ?? host,
            server: host,
            port: components.port ?? 443,
            uuid: uuid,
            serverName: first(query["sni"], tlsEnabled ? host : nil) ?? "",
            fingerprint: query["fp"] ?? "chrome",
            flow: "",
            proxyProtocol: .vmess,
            encryption: query["encryption"] ?? "auto",
            alterID: Int(query["aid"] ?? "") ?? 0,
            security: tlsEnabled ? .tls : .none,
            transport: transport,
            transportPath: transport == .grpc ? "" : (query["path"] ?? ""),
            transportHost: query["host"] ?? "",
            serviceName: transport == .grpc ? first(query["servicename"], query["path"]) ?? "" : "",
            allowInsecure: truthy(query["allowinsecure"]),
            alpn: query["alpn"] ?? ""
        )
        return try validated(profile)
    }

    private static func parseTrojan(_ value: String) throws -> VLESSProfile {
        guard let components = URLComponents(string: value),
              let host = components.host,
              let user = components.user?.removingPercentEncoding else {
            throw ProxyURLParserError.invalidLink("Trojan")
        }
        let password = joinedUserInfo(user: user, password: components.password?.removingPercentEncoding)
        guard !password.isEmpty else { throw ProxyURLParserError.invalidLink("Trojan") }
        let query = queryMap(components)
        if let security = query["security"]?.lowercased(), !security.isEmpty, security != "tls" {
            throw ProxyURLParserError.unsupportedOption("Trojan security=\(security)")
        }
        let transport = try parseTransport(query["type"])
        let path = query["path"] ?? ""
        let profile = VLESSProfile(
            name: decodedName(components) ?? host,
            server: host,
            port: components.port ?? 443,
            serverName: first(query["sni"], query["peer"], host) ?? host,
            fingerprint: query["fp"] ?? "chrome",
            flow: "",
            proxyProtocol: .trojan,
            password: password,
            security: .tls,
            transport: transport,
            transportPath: transport == .grpc ? "" : path,
            transportHost: first(query["host"], query["authority"]) ?? "",
            serviceName: transport == .grpc ? first(query["servicename"], path) ?? "" : "",
            allowInsecure: truthy(first(query["allowinsecure"], query["insecure"])),
            alpn: query["alpn"] ?? ""
        )
        return try validated(profile)
    }

    private static func parseShadowsocks(_ value: String) throws -> VLESSProfile {
        let raw = sharePayload(value)
        let endpointText: String
        if raw.contains("@") {
            endpointText = raw
        } else if let decoded = decodeBase64Text(raw) {
            endpointText = decoded
        } else {
            throw ProxyURLParserError.invalidLink("Shadowsocks")
        }

        let endpointWithoutFragment = endpointText.split(separator: "#", maxSplits: 1).first.map(String.init) ?? endpointText
        let endpointWithoutQuery = endpointWithoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? endpointWithoutFragment
        guard let at = endpointWithoutQuery.lastIndex(of: "@") else {
            throw ProxyURLParserError.invalidLink("Shadowsocks")
        }
        var credential = String(endpointWithoutQuery[..<at])
        let address = String(endpointWithoutQuery[endpointWithoutQuery.index(after: at)...])
        if let decoded = decodeBase64Text(credential) { credential = decoded }
        guard let colon = credential.firstIndex(of: ":") else {
            throw ProxyURLParserError.invalidLink("Shadowsocks")
        }
        let method = String(credential[..<colon])
        let password = String(credential[credential.index(after: colon)...]).removingPercentEncoding ?? String(credential[credential.index(after: colon)...])
        guard let endpoint = URLComponents(string: "ss://user@\(address)"),
              let host = endpoint.host,
              let port = endpoint.port else {
            throw ProxyURLParserError.invalidLink("Shadowsocks")
        }
        if let components = URLComponents(string: value),
           queryMap(components)["plugin"] != nil {
            throw ProxyURLParserError.unsupportedOption("Shadowsocks plugin")
        }
        let fragment = URLComponents(string: value)?.fragment?.removingPercentEncoding
        let profile = VLESSProfile(
            name: nonEmpty(fragment) ?? host,
            server: host,
            port: port,
            flow: "",
            proxyProtocol: .shadowsocks,
            password: password,
            encryption: method,
            security: .none
        )
        return try validated(profile)
    }

    private static func parseHysteria2(_ value: String) throws -> VLESSProfile {
        guard let components = URLComponents(string: value),
              let host = components.host,
              let user = components.user?.removingPercentEncoding else {
            throw ProxyURLParserError.invalidLink("Hysteria2")
        }
        let password = joinedUserInfo(user: user, password: components.password?.removingPercentEncoding)
        guard !password.isEmpty else { throw ProxyURLParserError.invalidLink("Hysteria2") }
        let query = queryMap(components)
        let obfs = query["obfs"] ?? ""
        if !obfs.isEmpty && obfs != "salamander" {
            throw ProxyURLParserError.unsupportedOption("Hysteria2 obfs=\(obfs)")
        }
        let profile = VLESSProfile(
            name: decodedName(components) ?? host,
            server: host,
            port: components.port ?? 443,
            serverName: first(query["sni"], host) ?? host,
            fingerprint: query["fp"] ?? "chrome",
            flow: "",
            proxyProtocol: .hysteria2,
            password: password,
            obfuscation: obfs,
            obfuscationPassword: first(query["obfs-password"], query["obfspassword"]) ?? "",
            security: .tls,
            allowInsecure: truthy(first(query["insecure"], query["allowinsecure"])),
            alpn: query["alpn"] ?? "h3"
        )
        return try validated(profile)
    }

    private static func parseTUIC(_ value: String) throws -> VLESSProfile {
        guard let components = URLComponents(string: value),
              let host = components.host,
              let uuid = components.user,
              UUID(uuidString: uuid) != nil,
              let password = components.password?.removingPercentEncoding,
              !password.isEmpty else {
            throw ProxyURLParserError.invalidLink("TUIC")
        }
        let query = queryMap(components)
        let congestion = first(query["congestion_control"], query["congestion-control"]) ?? "cubic"
        let relay = first(query["udp_relay_mode"], query["udp-relay-mode"]) ?? "native"
        guard ["cubic", "new_reno", "bbr"].contains(congestion), ["native", "quic"].contains(relay) else {
            throw ProxyURLParserError.unsupportedOption("TUIC congestion/UDP relay mode")
        }
        let profile = VLESSProfile(
            name: decodedName(components) ?? host,
            server: host,
            port: components.port ?? 443,
            uuid: uuid,
            serverName: first(query["sni"], host) ?? host,
            fingerprint: query["fp"] ?? "chrome",
            flow: "",
            proxyProtocol: .tuic,
            password: password,
            congestionControl: congestion,
            udpRelayMode: relay,
            security: .tls,
            allowInsecure: truthy(first(query["allow_insecure"], query["allowinsecure"], query["insecure"])),
            alpn: query["alpn"] ?? "h3"
        )
        return try validated(profile)
    }

    private static func validated(_ profile: VLESSProfile) throws -> VLESSProfile {
        if let message = profile.validationMessage { throw ProxyURLParserError.invalidLink(message) }
        return profile
    }

    private static func parseTransport(_ value: String?) throws -> VLESSTransport {
        switch value?.lowercased() ?? "tcp" {
        case "", "tcp", "raw": return .tcp
        case "ws", "websocket": return .webSocket
        case "grpc": return .grpc
        case "http", "h2", "http2": return .http2
        default: throw ProxyURLParserError.unsupportedOption("transport=\(value ?? "")")
        }
    }

    private static func queryMap(_ components: URLComponents) -> [String: String] {
        Dictionary(components.queryItems?.map { ($0.name.lowercased(), $0.value ?? "") } ?? [], uniquingKeysWith: { _, last in last })
    }

    private static func sharePayload(_ value: String) -> String {
        guard let range = value.range(of: "://") else { return "" }
        let payload = String(value[range.upperBound...])
        return String(payload.split(separator: "#", maxSplits: 1).first ?? "").removingPercentEncoding ?? payload
    }

    private static func decodeBase64(_ value: String) -> Data? {
        var normalized = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized.append(String(repeating: "=", count: (4 - normalized.count % 4) % 4))
        return Data(base64Encoded: normalized)
    }

    private static func decodeBase64Text(_ value: String) -> String? {
        decodeBase64(value).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func decodedName(_ components: URLComponents) -> String? {
        nonEmpty(components.fragment?.removingPercentEncoding)
    }

    private static func joinedUserInfo(user: String, password: String?) -> String {
        guard let password, !password.isEmpty else { return user }
        return "\(user):\(password)"
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        return Int(string(value))
    }

    private static func bool(_ value: Any?) -> Bool { truthy(string(value)) }
    private static func truthy(_ value: String?) -> Bool { ["1", "true", "yes"].contains(value?.lowercased() ?? "") }
    private static func nonEmpty(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
    private static func first(_ values: String?...) -> String? { values.compactMap(nonEmpty).first }
}
