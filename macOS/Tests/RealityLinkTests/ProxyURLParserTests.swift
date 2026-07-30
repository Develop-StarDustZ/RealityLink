import Foundation
import XCTest
@testable import RealityLink

final class ProxyURLParserTests: XCTestCase {
    func testParsesVMessV2RayNJSON() throws {
        let json: [String: Any] = [
            "v": "2", "ps": "VMess WS", "add": "vmess.example.com", "port": "443",
            "id": "00000000-0000-4000-8000-000000000101", "aid": "0", "scy": "auto",
            "net": "ws", "host": "cdn.example.com", "path": "/vmess", "tls": "tls",
            "sni": "edge.example.com", "fp": "chrome"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let link = "vmess://\(data.base64EncodedString())"

        let profile = try ProxyURLParser.parse(link)

        XCTAssertEqual(profile.proxyProtocol, .vmess)
        XCTAssertEqual(profile.transport, .webSocket)
        XCTAssertEqual(profile.transportHost, "cdn.example.com")
        XCTAssertEqual(profile.transportPath, "/vmess")
        XCTAssertEqual(profile.security, .tls)
    }

    func testParsesTrojanGRPC() throws {
        let link = "trojan://secret@example.com:443?security=tls&sni=edge.example.com&type=grpc&serviceName=Tunnel#Trojan"
        let profile = try ProxyURLParser.parse(link)

        XCTAssertEqual(profile.proxyProtocol, .trojan)
        XCTAssertEqual(profile.password, "secret")
        XCTAssertEqual(profile.transport, .grpc)
        XCTAssertEqual(profile.serviceName, "Tunnel")
    }

    func testParsesShadowsocksSIP002() throws {
        let credential = Data("aes-256-gcm:test-password".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let profile = try ProxyURLParser.parse("ss://\(credential)@203.0.113.5:8388#SS%20Node")

        XCTAssertEqual(profile.proxyProtocol, .shadowsocks)
        XCTAssertEqual(profile.encryption, "aes-256-gcm")
        XCTAssertEqual(profile.password, "test-password")
        XCTAssertEqual(profile.server, "203.0.113.5")
        XCTAssertEqual(profile.name, "SS Node")
    }

    func testParsesLegacyWholePayloadShadowsocks() throws {
        let payload = Data("chacha20-ietf-poly1305:password@example.com:8388".utf8).base64EncodedString()
        let profile = try ProxyURLParser.parse("ss://\(payload)#Legacy")

        XCTAssertEqual(profile.encryption, "chacha20-ietf-poly1305")
        XCTAssertEqual(profile.server, "example.com")
        XCTAssertEqual(profile.port, 8388)
    }

    func testParsesHysteria2SIP() throws {
        let link = "hysteria2://user%3Apass@hy2.example.com:8443?sni=edge.example.com&insecure=1&obfs=salamander&obfs-password=obfsSecret#HY2"
        let profile = try ProxyURLParser.parse(link)

        XCTAssertEqual(profile.proxyProtocol, .hysteria2)
        XCTAssertEqual(profile.password, "user:pass")
        XCTAssertEqual(profile.obfuscation, "salamander")
        XCTAssertEqual(profile.obfuscationPassword, "obfsSecret")
        XCTAssertTrue(profile.allowInsecure)
    }

    func testParsesTUICLink() throws {
        let link = "tuic://00000000-0000-4000-8000-000000000102:tuic-pass@tuic.example.com:443?sni=edge.example.com&congestion_control=bbr&udp_relay_mode=native&allow_insecure=1#TUIC"
        let profile = try ProxyURLParser.parse(link)

        XCTAssertEqual(profile.proxyProtocol, .tuic)
        XCTAssertEqual(profile.uuid, "00000000-0000-4000-8000-000000000102")
        XCTAssertEqual(profile.password, "tuic-pass")
        XCTAssertEqual(profile.congestionControl, "bbr")
        XCTAssertEqual(profile.udpRelayMode, "native")
    }

    func testRejectsUnsupportedHysteria2Obfuscation() {
        XCTAssertThrowsError(try ProxyURLParser.parse("hy2://pass@example.com:443?obfs=unknown"))
    }

    func testRejectsShadowsocksPluginRatherThanSilentlyIgnoringIt() {
        let credential = Data("aes-256-gcm:password".utf8).base64EncodedString()
        XCTAssertThrowsError(try ProxyURLParser.parse("ss://\(credential)@example.com:8388?plugin=v2ray-plugin"))
    }

    func testRejectsTrojanRealityRatherThanTreatingItAsTLS() {
        XCTAssertThrowsError(try ProxyURLParser.parse("trojan://password@example.com:443?security=reality&pbk=key&sni=example.com"))
    }
}
