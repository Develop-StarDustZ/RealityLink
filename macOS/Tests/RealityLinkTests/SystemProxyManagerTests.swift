import XCTest
@testable import RealityLink

final class SystemProxyManagerTests: XCTestCase {
    func testParsesNetworkSetupProxyOutput() throws {
        let output = """
        Enabled: Yes
        Server: 127.0.0.1
        Port: 20890
        Authenticated Proxy Enabled: 0
        """

        XCTAssertEqual(
            ProxyEndpoint.parse(output),
            ProxyEndpoint(enabled: true, server: "127.0.0.1", port: 20_890, authenticated: false)
        )
    }

    func testParsesDisabledEmptyProxy() throws {
        let output = """
        Enabled: No
        Server:
        Port: 0
        Authenticated Proxy Enabled: 0
        """

        XCTAssertEqual(
            ProxyEndpoint.parse(output),
            ProxyEndpoint(enabled: false, server: "", port: 0, authenticated: false)
        )
    }
}
