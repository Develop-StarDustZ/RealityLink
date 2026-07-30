import XCTest
@testable import RealityLink

final class SingBoxConfigurationTests: XCTestCase {
    func testSystemProxyConfiguration() throws {
        let data = try SingBoxConfiguration.make(profile: .preview, settings: AppSettings())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbounds = try XCTUnwrap(root["inbounds"] as? [[String: Any]])
        let outbound = try XCTUnwrap((root["outbounds"] as? [[String: Any]])?.first)

        XCTAssertEqual(inbounds.first?["type"] as? String, "mixed")
        XCTAssertEqual(inbounds.first?["set_system_proxy"] as? Bool, false)
        XCTAssertEqual(outbound["type"] as? String, "vless")

        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        let reality = try XCTUnwrap(tls["reality"] as? [String: Any])
        XCTAssertEqual(reality["enabled"] as? Bool, true)
    }

    func testTUNConfiguration() throws {
        var settings = AppSettings()
        settings.connectionMode = .tun
        let data = try SingBoxConfiguration.make(profile: .preview, settings: settings)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let inbound = try XCTUnwrap((root["inbounds"] as? [[String: Any]])?.first)

        XCTAssertEqual(inbound["type"] as? String, "tun")
        XCTAssertNil(inbound["interface_name"], "Darwin must automatically allocate an utun name")
        XCTAssertEqual(inbound["auto_route"] as? Bool, true)
        XCTAssertEqual(inbound["strict_route"] as? Bool, true)
    }

    func testTLSWebSocketConfiguration() throws {
        let profile = tlsProfile(transport: .webSocket, path: "/ws", host: "cdn.example.com")
        let outbound = try outbound(for: profile)
        let tls = try XCTUnwrap(outbound["tls"] as? [String: Any])
        let transport = try XCTUnwrap(outbound["transport"] as? [String: Any])

        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertNil(tls["reality"])
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/ws")
        XCTAssertEqual((transport["headers"] as? [String: String])?["Host"], "cdn.example.com")
    }

    func testTLSGRPCConfiguration() throws {
        var profile = tlsProfile(transport: .grpc)
        profile.serviceName = "TunnelService"
        let transport = try XCTUnwrap((try outbound(for: profile))["transport"] as? [String: Any])

        XCTAssertEqual(transport["type"] as? String, "grpc")
        XCTAssertEqual(transport["service_name"] as? String, "TunnelService")
    }

    func testTLSHTTP2Configuration() throws {
        let profile = tlsProfile(transport: .http2, path: "/h2", host: "one.example.com,two.example.com")
        let transport = try XCTUnwrap((try outbound(for: profile))["transport"] as? [String: Any])

        XCTAssertEqual(transport["type"] as? String, "http")
        XCTAssertEqual(transport["path"] as? String, "/h2")
        XCTAssertEqual(transport["host"] as? [String], ["one.example.com", "two.example.com"])
    }

    func testVMessConfiguration() throws {
        let outbound = try outbound(for: vmessProfile())
        XCTAssertEqual(outbound["type"] as? String, "vmess")
        XCTAssertEqual(outbound["security"] as? String, "auto")
        XCTAssertEqual(outbound["alter_id"] as? Int, 0)
    }

    func testTrojanConfiguration() throws {
        let outbound = try outbound(for: trojanProfile())
        XCTAssertEqual(outbound["type"] as? String, "trojan")
        XCTAssertEqual(outbound["password"] as? String, "trojan-password")
        XCTAssertNotNil(outbound["tls"])
    }

    func testShadowsocksConfiguration() throws {
        let outbound = try outbound(for: shadowsocksProfile())
        XCTAssertEqual(outbound["type"] as? String, "shadowsocks")
        XCTAssertEqual(outbound["method"] as? String, "aes-256-gcm")
        XCTAssertNil(outbound["tls"])
    }

    func testHysteria2Configuration() throws {
        let outbound = try outbound(for: hysteria2Profile())
        XCTAssertEqual(outbound["type"] as? String, "hysteria2")
        XCTAssertEqual((outbound["obfs"] as? [String: String])?["type"], "salamander")
        XCTAssertNotNil(outbound["tls"])
    }

    func testTUICConfiguration() throws {
        let outbound = try outbound(for: tuicProfile())
        XCTAssertEqual(outbound["type"] as? String, "tuic")
        XCTAssertEqual(outbound["congestion_control"] as? String, "bbr")
        XCTAssertEqual(outbound["udp_relay_mode"] as? String, "native")
    }

    func testInstalledSingBoxAcceptsBothModes() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let bundledCore = repositoryRoot
            .appendingPathComponent("dist/macos/arm64/RealityLink.app/Contents/Resources/sing-box").path
        let corePaths = [bundledCore, "/opt/homebrew/bin/sing-box", "/usr/local/bin/sing-box"]
        guard let corePath = corePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("sing-box is not installed")
        }

        let profiles = [
            VLESSProfile.preview,
            tlsProfile(transport: .tcp),
            tlsProfile(transport: .webSocket, path: "/ws", host: "cdn.example.com"),
            tlsProfile(transport: .grpc),
            tlsProfile(transport: .http2, path: "/h2", host: "h2.example.com"),
            vmessProfile(), trojanProfile(), shadowsocksProfile(), hysteria2Profile(), tuicProfile()
        ]
        for mode in ConnectionMode.allCases {
            var settings = AppSettings()
            settings.connectionMode = mode
            for profile in profiles {
                let data = try SingBoxConfiguration.make(profile: profile, settings: settings)
                let fileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("realitylink-\(mode.rawValue)-\(UUID().uuidString).json")
                try data.write(to: fileURL)
                defer { try? FileManager.default.removeItem(at: fileURL) }

                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: corePath)
                process.arguments = ["check", "-c", fileURL.path]
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                process.waitUntilExit()

                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                XCTAssertEqual(process.terminationStatus, 0, "\(mode.title) \(profile.transport.rawValue): \(output)")
            }
        }
    }

    private func outbound(for profile: VLESSProfile) throws -> [String: Any] {
        let data = try SingBoxConfiguration.make(profile: profile, settings: AppSettings())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((root["outbounds"] as? [[String: Any]])?.first)
    }

    private func tlsProfile(transport: VLESSTransport, path: String = "", host: String = "") -> VLESSProfile {
        VLESSProfile(
            name: "TLS Test",
            server: "vpn.example.com",
            uuid: "00000000-0000-4000-8000-000000000099",
            serverName: "vpn.example.com",
            fingerprint: "chrome",
            flow: "",
            security: .tls,
            transport: transport,
            transportPath: path,
            transportHost: host,
            serviceName: "TunnelService",
            alpn: transport == .http2 ? "h2" : ""
        )
    }

    private func vmessProfile() -> VLESSProfile {
        VLESSProfile(
            name: "VMess", server: "vmess.example.com", uuid: "00000000-0000-4000-8000-000000000201",
            serverName: "vmess.example.com", flow: "", proxyProtocol: .vmess, encryption: "auto",
            security: .tls, transport: .webSocket, transportPath: "/ws", transportHost: "cdn.example.com"
        )
    }

    private func trojanProfile() -> VLESSProfile {
        VLESSProfile(
            name: "Trojan", server: "trojan.example.com", serverName: "trojan.example.com", flow: "",
            proxyProtocol: .trojan, password: "trojan-password", security: .tls, transport: .grpc,
            serviceName: "TunnelService"
        )
    }

    private func shadowsocksProfile() -> VLESSProfile {
        VLESSProfile(
            name: "Shadowsocks", server: "ss.example.com", port: 8388, flow: "",
            proxyProtocol: .shadowsocks, password: "ss-password", encryption: "aes-256-gcm", security: .none
        )
    }

    private func hysteria2Profile() -> VLESSProfile {
        VLESSProfile(
            name: "Hysteria2", server: "hy2.example.com", serverName: "hy2.example.com", flow: "",
            proxyProtocol: .hysteria2, password: "hy2-password", obfuscation: "salamander",
            obfuscationPassword: "obfs-password", security: .tls, alpn: "h3"
        )
    }

    private func tuicProfile() -> VLESSProfile {
        VLESSProfile(
            name: "TUIC", server: "tuic.example.com", uuid: "00000000-0000-4000-8000-000000000202",
            serverName: "tuic.example.com", flow: "", proxyProtocol: .tuic, password: "tuic-password",
            congestionControl: "bbr", udpRelayMode: "native", security: .tls, alpn: "h3"
        )
    }
}
