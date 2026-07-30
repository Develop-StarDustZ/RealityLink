import Foundation

enum VLESSURLParserError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedSecurity
    case unsupportedTransport
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "这不是有效的 VLESS 链接"
        case .unsupportedSecurity:
            return "链接不是支持的 VLESS + Reality/TLS 节点"
        case .unsupportedTransport:
            return "不支持这个 VLESS 传输方式（Reality 仅支持 TCP/raw）"
        case .missingField(let field):
            return "链接缺少必要字段：\(field)"
        }
    }
}

enum VLESSURLParser {
    static func parse(_ text: String) throws -> VLESSProfile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "vless" else {
            throw VLESSURLParserError.invalidURL
        }

        let query = Dictionary(
            components.queryItems?.map { ($0.name.lowercased(), $0.value ?? "") } ?? [],
            uniquingKeysWith: { _, newest in newest }
        )
        let endpoint = try parseEndpoint(components: components, rawText: trimmed)

        let securityValue = query["security"]?.lowercased()
        let isStandardReality = securityValue == "reality"
        let isLegacyReality = query["xtls"] == "2" && !(query["pbk"] ?? "").isEmpty
        let isTLS = securityValue == "tls" || (!isLegacyReality && query["tls"] == "1")
        guard isStandardReality || isLegacyReality || isTLS else {
            throw VLESSURLParserError.unsupportedSecurity
        }

        let transport = try parseTransport(query["type"])
        if (isStandardReality || isLegacyReality) && transport != .tcp {
            throw VLESSURLParserError.unsupportedTransport
        }
        if let obfs = query["obfs"], !obfs.isEmpty,
           !["none", "tcp", "raw"].contains(obfs.lowercased()) {
            throw VLESSURLParserError.unsupportedTransport
        }

        let serverName = firstNonEmpty(query["sni"], query["peer"], query["servername"], isTLS ? endpoint.host : nil)
        guard let serverName else {
            throw VLESSURLParserError.missingField("sni / peer")
        }
        let publicKey = query["pbk"] ?? ""
        if !isTLS && publicKey.isEmpty { throw VLESSURLParserError.missingField("pbk") }

        let decodedName = components.fragment?.removingPercentEncoding
        let remarks = query["remarks"]?.removingPercentEncoding
        let name = firstNonEmpty(decodedName, remarks) ?? endpoint.host
        let flow = transport == .tcp ? (query["flow"] ?? (query["xtls"] == "2" ? "xtls-rprx-vision" : "")) : ""
        let transportHost = firstNonEmpty(query["host"], query["authority"]) ?? ""
        let path = (query["path"] ?? "").removingPercentEncoding ?? (query["path"] ?? "")
        let serviceName = firstNonEmpty(query["servicename"], query["service_name"], path) ?? ""
        let insecureValue = firstNonEmpty(query["allowinsecure"], query["insecure"])?.lowercased()
        let profile = VLESSProfile(
            name: name,
            server: endpoint.host,
            port: endpoint.port,
            uuid: endpoint.uuid,
            serverName: serverName,
            publicKey: publicKey,
            shortID: query["sid"] ?? "",
            fingerprint: query["fp"].flatMap { $0.isEmpty ? nil : $0 } ?? "chrome",
            flow: flow,
            security: isTLS ? .tls : .reality,
            transport: transport,
            transportPath: transport == .grpc ? "" : path,
            transportHost: transportHost,
            serviceName: transport == .grpc ? serviceName : "",
            allowInsecure: ["1", "true", "yes"].contains(insecureValue ?? ""),
            alpn: query["alpn"]?.removingPercentEncoding ?? ""
        )

        if let message = profile.validationMessage {
            throw VLESSURLParserError.missingField(message)
        }
        return profile
    }

    private static func parseTransport(_ value: String?) throws -> VLESSTransport {
        switch value?.lowercased() ?? "tcp" {
        case "", "tcp", "raw": return .tcp
        case "ws", "websocket": return .webSocket
        case "grpc": return .grpc
        case "http", "h2", "http2": return .http2
        default: throw VLESSURLParserError.unsupportedTransport
        }
    }

    private static func parseEndpoint(components: URLComponents, rawText: String) throws -> Endpoint {
        if let host = components.host,
           !host.isEmpty,
           let user = components.user,
           UUID(uuidString: user) != nil {
            return Endpoint(host: host, port: components.port ?? 443, uuid: user)
        }

        guard let schemeSeparator = rawText.range(of: "://"),
              schemeSeparator.upperBound < rawText.endIndex else {
            throw VLESSURLParserError.invalidURL
        }
        let remainder = rawText[schemeSeparator.upperBound...]
        let payloadEnd = remainder.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? remainder.endIndex
        let encodedPayload = String(remainder[..<payloadEnd]).removingPercentEncoding ?? String(remainder[..<payloadEnd])
        guard let decoded = decodeBase64URL(encodedPayload) else {
            throw VLESSURLParserError.invalidURL
        }

        let address: String
        if let atIndex = decoded.firstIndex(of: "@"),
           let colonIndex = decoded[..<atIndex].firstIndex(of: ":") {
            let encryption = String(decoded[..<colonIndex]).lowercased()
            guard encryption == "none" else {
                throw VLESSURLParserError.invalidURL
            }
            address = String(decoded[decoded.index(after: colonIndex)...])
        } else {
            address = decoded
        }

        guard let endpointComponents = URLComponents(string: "vless://\(address)"),
              let host = endpointComponents.host,
              !host.isEmpty,
              let uuid = endpointComponents.user,
              UUID(uuidString: uuid) != nil else {
            throw VLESSURLParserError.invalidURL
        }
        return Endpoint(host: host, port: endpointComponents.port ?? 443, uuid: uuid)
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - normalized.count % 4) % 4
        normalized.append(String(repeating: "=", count: padding))
        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first(where: { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) ?? nil
    }

    private struct Endpoint {
        let host: String
        let port: Int
        let uuid: String
    }
}
