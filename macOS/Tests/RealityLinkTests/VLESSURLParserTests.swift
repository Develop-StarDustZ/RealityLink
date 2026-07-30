import XCTest
@testable import RealityLink

final class VLESSURLParserTests: XCTestCase {
    func testParsesRealityShareURL() throws {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:8443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.example.com&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef&type=tcp#Tokyo%20Node"

        let profile = try VLESSURLParser.parse(link)

        XCTAssertEqual(profile.name, "Tokyo Node")
        XCTAssertEqual(profile.server, "vpn.example.com")
        XCTAssertEqual(profile.port, 8443)
        XCTAssertEqual(profile.serverName, "www.example.com")
        XCTAssertEqual(profile.shortID, "0123456789abcdef")
        XCTAssertEqual(profile.flow, "xtls-rprx-vision")
    }

    func testParsesTLSTCPLink() throws {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=tls&type=tcp&sni=example.com&fp=chrome&alpn=h2%2Chttp%2F1.1#TLS"
        let profile = try VLESSURLParser.parse(link)

        XCTAssertEqual(profile.security, .tls)
        XCTAssertEqual(profile.transport, .tcp)
        XCTAssertEqual(profile.serverName, "example.com")
        XCTAssertEqual(profile.alpn, "h2,http/1.1")
        XCTAssertTrue(profile.publicKey.isEmpty)
    }

    func testParsesTLSWebSocketLink() throws {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=tls&type=ws&sni=edge.example.com&host=cdn.example.com&path=%2Fvless%3Fed%3D2048#WS"
        let profile = try VLESSURLParser.parse(link)

        XCTAssertEqual(profile.transport, .webSocket)
        XCTAssertEqual(profile.transportHost, "cdn.example.com")
        XCTAssertEqual(profile.transportPath, "/vless?ed=2048")
        XCTAssertEqual(profile.flow, "")
    }

    func testParsesTLSGRPCLink() throws {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=tls&type=grpc&sni=edge.example.com&serviceName=RealityLink#GRPC"
        let profile = try VLESSURLParser.parse(link)

        XCTAssertEqual(profile.transport, .grpc)
        XCTAssertEqual(profile.serviceName, "RealityLink")
    }

    func testParsesTLSHTTP2Link() throws {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=tls&type=h2&sni=edge.example.com&host=h2.example.com&path=%2Ftunnel#H2"
        let profile = try VLESSURLParser.parse(link)

        XCTAssertEqual(profile.transport, .http2)
        XCTAssertEqual(profile.transportHost, "h2.example.com")
        XCTAssertEqual(profile.transportPath, "/tunnel")
    }

    func testRejectsUnsupportedSecurity() {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=none&type=tcp"
        XCTAssertThrowsError(try VLESSURLParser.parse(link)) { error in
            XCTAssertEqual(error as? VLESSURLParserError, .unsupportedSecurity)
        }
    }

    func testRejectsUnsupportedTransport() {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=reality&sni=example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&type=grpc"
        XCTAssertThrowsError(try VLESSURLParser.parse(link)) { error in
            XCTAssertEqual(error as? VLESSURLParserError, .unsupportedTransport)
        }
    }

    func testDoesNotInventMissingFlow() throws {
        let link = "vless://123e4567-e89b-12d3-a456-426614174000@vpn.example.com:443?security=reality&sni=example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&type=tcp"
        XCTAssertEqual(try VLESSURLParser.parse(link).flow, "")
    }

    func testParsesLegacyBase64RealityURL() throws {
        let link = "vless://bm9uZToxMjNlNDU2Ny1lODliLTEyZDMtYTQ1Ni00MjY2MTQxNzQwMDBAMjAzLjAuMTEzLjEwOjQ4MTQz?remarks=Legacy-Test&obfs=none&tls=1&peer=legacy.example.com&xtls=2&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=6f71"

        let profile = try VLESSURLParser.parse(link)

        XCTAssertEqual(profile.name, "Legacy-Test")
        XCTAssertEqual(profile.server, "203.0.113.10")
        XCTAssertEqual(profile.port, 48143)
        XCTAssertEqual(profile.uuid, "123e4567-e89b-12d3-a456-426614174000")
        XCTAssertEqual(profile.serverName, "legacy.example.com")
        XCTAssertEqual(profile.publicKey, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
        XCTAssertEqual(profile.shortID, "6f71")
        XCTAssertEqual(profile.flow, "xtls-rprx-vision")
        XCTAssertEqual(profile.fingerprint, "chrome")
    }
}
