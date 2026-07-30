import Foundation
import XCTest
@testable import RealityLink

final class SubscriptionImporterTests: XCTestCase {
    private let firstLink = "vless://00000000-0000-4000-8000-000000000000@192.0.2.10:48143?security=reality&type=tcp&sni=www.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=6f71#First"
    private let secondLink = "vless://00000000-0000-4000-8000-000000000001@example.net:443?security=reality&type=raw&sni=cdn.example.net&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef#Second"

    func testDecodesPercentEncodedSubscriptionURL() throws {
        let result = try SubscriptionImporter.subscriptionURL(
            from: "sub://https%3A%2F%2Fexample.com%2Fsubscribe%3Ftoken%3Dabc"
        )

        XCTAssertEqual(result.absoluteString, "https://example.com/subscribe?token=abc")
    }

    func testAcceptsDirectHTTPSubscriptionWithIPAndPort() throws {
        let source = "http://192.0.2.10:8082/sub/example"

        let result = try SubscriptionImporter.subscriptionURL(from: source)

        XCTAssertEqual(result.absoluteString, source)
        XCTAssertEqual(result.scheme, "http")
        XCTAssertEqual(result.host, "192.0.2.10")
        XCTAssertEqual(result.port, 8_082)
    }

    func testDecodesBase64URLSubscriptionURL() throws {
        let source = "https://example.com/api/sub?token=abc"
        let encoded = Data(source.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let result = try SubscriptionImporter.subscriptionURL(from: "sub://\(encoded)")

        XCTAssertEqual(result.absoluteString, source)
    }

    func testRejectsNonWebSubscriptionTarget() {
        XCTAssertThrowsError(try SubscriptionImporter.subscriptionURL(from: "sub://file%3A%2F%2F%2Ftmp%2Fnodes"))
    }

    func testParsesPlainSubscriptionAndSkipsUnsupportedNodes() throws {
        let unsupported = "vless://00000000-0000-4000-8000-000000000002@example.org:443?security=reality&type=grpc&sni=example.org&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let body = [firstLink, "vmess://ignored", unsupported, secondLink].joined(separator: "\n")

        let profiles = try SubscriptionImporter.parseProfiles(from: Data(body.utf8))

        XCTAssertEqual(profiles.map(\.name), ["First", "Second"])
    }

    func testParsesWholeBodyBase64AndRemovesDuplicates() throws {
        let body = [firstLink, firstLink, secondLink].joined(separator: "\r\n")
        let encoded = Data(body.utf8).base64EncodedString()

        let profiles = try SubscriptionImporter.parseProfiles(from: Data(encoded.utf8))

        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles.map(\.server), ["192.0.2.10", "example.net"])
    }

    func testSubscriptionImportsAllSupportedTLSTransports() throws {
        let base = "vless://00000000-0000-4000-8000-000000000041@vpn.example.com:443?security=tls&sni=vpn.example.com"
        let links = [
            "\(base)&type=tcp#TCP",
            "\(base)&type=ws&host=cdn.example.com&path=%2Fws#WS",
            "\(base)&type=grpc&serviceName=TunnelService#GRPC",
            "\(base)&type=h2&host=h2.example.com&path=%2Fh2#H2"
        ]

        let profiles = try SubscriptionImporter.parseProfiles(from: Data(links.joined(separator: "\n").utf8))

        XCTAssertEqual(Set(profiles.map(\.transport)), Set(VLESSTransport.allCases))
    }

    func testSubscriptionImportsAllSupportedProtocols() throws {
        let vmessJSON: [String: Any] = [
            "v": "2", "ps": "VMess", "add": "vmess.example.com", "port": "443",
            "id": "00000000-0000-4000-8000-000000000051", "aid": "0", "net": "tcp", "tls": ""
        ]
        let vmess = "vmess://\((try JSONSerialization.data(withJSONObject: vmessJSON)).base64EncodedString())"
        let ssCredential = Data("aes-256-gcm:password".utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let links = [
            firstLink,
            vmess,
            "trojan://password@trojan.example.com:443?sni=trojan.example.com#Trojan",
            "ss://\(ssCredential)@ss.example.com:8388#SS",
            "hy2://password@hy2.example.com:443?sni=hy2.example.com#HY2",
            "tuic://00000000-0000-4000-8000-000000000052:password@tuic.example.com:443?sni=tuic.example.com#TUIC"
        ]

        let profiles = try SubscriptionImporter.parseProfiles(from: Data(links.joined(separator: "\n").utf8))

        XCTAssertEqual(Set(profiles.map(\.proxyProtocol)), Set(ProxyProtocol.allCases))
    }

    func testReportsSubscriptionWithoutCompatibleNodes() {
        XCTAssertThrowsError(try SubscriptionImporter.parseProfiles(from: Data("vmess://nothing-here".utf8))) { error in
            XCTAssertEqual(error as? SubscriptionImportError, .noCompatibleNodes)
        }
    }
}
