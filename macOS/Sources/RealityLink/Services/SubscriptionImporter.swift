import Foundation

enum SubscriptionImportError: LocalizedError, Equatable {
    case invalidLink
    case unsupportedScheme
    case downloadFailed(Int)
    case responseTooLarge
    case unreadableResponse
    case noCompatibleNodes

    var errorDescription: String? {
        message(for: .english)
    }

    func message(for language: AppLanguage) -> String {
        switch self {
        case .invalidLink:
            return L10n.t("subscriptionInvalid", language)
        case .unsupportedScheme:
            return L10n.t("subscriptionScheme", language)
        case .downloadFailed(let status):
            return L10n.t("subscriptionHTTPError", language, status)
        case .responseTooLarge:
            return L10n.t("subscriptionTooLarge", language)
        case .unreadableResponse:
            return L10n.t("subscriptionUnreadable", language)
        case .noCompatibleNodes:
            return L10n.t("subscriptionNoNodes", language)
        }
    }
}

enum SubscriptionImporter {
    private static let maximumResponseSize = 2 * 1_024 * 1_024

    static func isSubscriptionLink(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.hasPrefix("sub://") || value.hasPrefix("https://") || value.hasPrefix("http://")
    }

    static func fetchProfiles(from text: String) async throws -> [VLESSProfile] {
        let url = try subscriptionURL(from: text)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("RealityLink/0.2.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/octet-stream, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let response = response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            throw SubscriptionImportError.downloadFailed(response.statusCode)
        }
        guard data.count <= maximumResponseSize else {
            throw SubscriptionImportError.responseTooLarge
        }
        return try parseProfiles(from: data)
    }

    static func subscriptionURL(from text: String) throws -> URL {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw SubscriptionImportError.invalidLink }

        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return try validatedWebURL(value)
        }
        guard value.lowercased().hasPrefix("sub://") else {
            throw SubscriptionImportError.unsupportedScheme
        }

        let payload = String(value.dropFirst("sub://".count))
        let withoutFragment = String(payload.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        let percentDecoded = withoutFragment.removingPercentEncoding ?? withoutFragment
        var candidates = [percentDecoded]
        if let decoded = decodeBase64Text(percentDecoded) { candidates.append(decoded) }
        if percentDecoded != withoutFragment, let decoded = decodeBase64Text(withoutFragment) { candidates.append(decoded) }

        for candidate in candidates {
            if let url = try? validatedWebURL(candidate.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return url
            }
        }
        throw SubscriptionImportError.invalidLink
    }

    static func subscriptionName(from text: String) -> String {
        guard let url = try? subscriptionURL(from: text) else { return "Subscription" }
        let lastComponent = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if !lastComponent.isEmpty, lastComponent != "/" {
            return lastComponent
        }
        return url.host ?? "Subscription"
    }

    static func parseProfiles(from data: Data) throws -> [VLESSProfile] {
        guard data.count <= maximumResponseSize else {
            throw SubscriptionImportError.responseTooLarge
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw SubscriptionImportError.unreadableResponse
        }

        var documents = [text]
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decoded = decodeBase64Text(compact), decoded != compact {
            documents.append(decoded)
        }

        var profiles: [VLESSProfile] = []
        var seen = Set<ProfileKey>()
        for document in documents {
            for link in extractProxyLinks(from: document) {
                guard let profile = try? ProxyURLParser.parse(link) else { continue }
                let key = ProfileKey(profile)
                if seen.insert(key).inserted {
                    profiles.append(profile)
                }
            }
        }
        guard !profiles.isEmpty else {
            throw SubscriptionImportError.noCompatibleNodes
        }
        return profiles
    }

    private static func validatedWebURL(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              let url = components.url else {
            throw SubscriptionImportError.invalidLink
        }
        return url
    }

    private static func decodeBase64Text(_ value: String) -> String? {
        let compact = value.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !compact.isEmpty else { return nil }
        var normalized = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        normalized.append(String(repeating: "=", count: (4 - normalized.count % 4) % 4))
        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        return decoded
    }

    private static func extractProxyLinks(from text: String) -> [String] {
        let pattern = #"(?i)(?:vless|vmess|trojan|ss|hysteria2|hy2|tuic)://[^\s\"'<>]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ",;]}"))
        }
    }

    private struct ProfileKey: Hashable {
        let server: String
        let port: Int
        let uuid: String
        let serverName: String
        let publicKey: String
        let shortID: String
        let security: VLESSSecurity
        let transport: VLESSTransport
        let transportPath: String
        let transportHost: String
        let serviceName: String
        let proxyProtocol: ProxyProtocol
        let password: String
        let encryption: String
        let obfuscation: String
        let obfuscationPassword: String
        let congestionControl: String
        let udpRelayMode: String

        init(_ profile: VLESSProfile) {
            server = profile.server.lowercased()
            port = profile.port
            uuid = profile.uuid.lowercased()
            serverName = profile.serverName.lowercased()
            publicKey = profile.publicKey
            shortID = profile.shortID.lowercased()
            security = profile.security
            transport = profile.transport
            transportPath = profile.transportPath
            transportHost = profile.transportHost.lowercased()
            serviceName = profile.serviceName
            proxyProtocol = profile.proxyProtocol
            password = profile.password
            encryption = profile.encryption
            obfuscation = profile.obfuscation
            obfuscationPassword = profile.obfuscationPassword
            congestionControl = profile.congestionControl
            udpRelayMode = profile.udpRelayMode
        }
    }
}
