import Foundation
import XCTest
@testable import RealityLink

@MainActor
final class SubscriptionGroupTests: XCTestCase {
    func testOldProfileJSONWithoutSubscriptionIDStillDecodes() throws {
        let json = #"{"id":"00000000-0000-4000-8000-000000000010","name":"Old node","server":"example.com","port":443,"uuid":"00000000-0000-4000-8000-000000000011","serverName":"cdn.example.com","publicKey":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","shortID":"","fingerprint":"chrome","flow":"xtls-rprx-vision"}"#

        let profile = try JSONDecoder().decode(VLESSProfile.self, from: Data(json.utf8))

        XCTAssertNil(profile.subscriptionID)
        XCTAssertEqual(profile.name, "Old node")
        XCTAssertEqual(profile.security, .reality)
        XCTAssertEqual(profile.transport, .tcp)
    }

    func testSubscriptionSyncPreservesMatchingIDAndReplacesRemovedNode() {
        let defaults = temporaryDefaults()
        let model = AppModel(defaults: defaults)
        let subscription = SubscriptionGroup(name: "Example subscription", sourceURL: "http://example.com/sub/example")
        model.subscriptions.append(subscription)

        let first = profile(server: "one.example.com", uuid: "00000000-0000-4000-8000-000000000021", name: "One")
        let removed = profile(server: "old.example.com", uuid: "00000000-0000-4000-8000-000000000022", name: "Old")
        model.apply([first, removed], to: subscription.id)
        let preservedID = model.profiles.first(where: { $0.server == first.server })?.id

        let updated = profile(server: "one.example.com", uuid: first.uuid, name: "One renamed")
        let added = profile(server: "new.example.com", uuid: "00000000-0000-4000-8000-000000000023", name: "New")
        model.apply([updated, added], to: subscription.id)

        XCTAssertEqual(model.profiles(in: subscription).count, 2)
        XCTAssertEqual(model.profiles.first(where: { $0.server == updated.server })?.id, preservedID)
        XCTAssertEqual(model.profiles.first(where: { $0.server == updated.server })?.name, "One renamed")
        XCTAssertFalse(model.profiles.contains(where: { $0.server == removed.server }))
        XCTAssertTrue(model.profiles.contains(where: { $0.server == added.server }))
    }

    func testNewSubscriptionAdoptsMatchingLocalNode() {
        let model = AppModel(defaults: temporaryDefaults())
        let local = profile(server: "one.example.com", uuid: "00000000-0000-4000-8000-000000000031", name: "Local")
        model.add(local)
        let subscription = SubscriptionGroup(name: "Group", sourceURL: "https://example.com/sub")
        model.subscriptions.append(subscription)

        var remote = local
        remote.id = UUID()
        remote.name = "From subscription"
        model.apply([remote], to: subscription.id, adoptingLocalMatches: true)

        XCTAssertTrue(model.localProfiles.isEmpty)
        XCTAssertEqual(model.profiles(in: subscription).count, 1)
        XCTAssertEqual(model.profiles(in: subscription).first?.id, local.id)
    }

    func testProtocolSpecificFieldsSurviveJSONRoundTrip() throws {
        let original = VLESSProfile(
            name: "TUIC", server: "tuic.example.com", uuid: "00000000-0000-4000-8000-000000000301",
            serverName: "tuic.example.com", flow: "", proxyProtocol: .tuic, password: "secret",
            congestionControl: "bbr", udpRelayMode: "quic", security: .tls, allowInsecure: true, alpn: "h3"
        )

        let decoded = try JSONDecoder().decode(VLESSProfile.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
    }

    private func profile(server: String, uuid: String, name: String) -> VLESSProfile {
        VLESSProfile(
            name: name,
            server: server,
            uuid: uuid,
            serverName: "cdn.example.com",
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        )
    }

    private func temporaryDefaults() -> UserDefaults {
        let suite = "RealityLinkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
