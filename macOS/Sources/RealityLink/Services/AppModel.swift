import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var profiles: [VLESSProfile] {
        didSet { saveProfiles() }
    }
    @Published var subscriptions: [SubscriptionGroup] {
        didSet { saveSubscriptions() }
    }
    @Published var latencyResults: [UUID: LatencyStatus] = [:]
    @Published var selectedProfileID: UUID? {
        didSet {
            UserDefaults.standard.set(selectedProfileID?.uuidString, forKey: Keys.selectedProfileID)
        }
    }
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    private enum Keys {
        static let profiles = "profiles"
        static let settings = "settings"
        static let subscriptions = "subscriptions"
        static let selectedProfileID = "selectedProfileID"
        static let language = "appLanguage"
    }

    init(defaults: UserDefaults = .standard) {
        language = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .english
        let decoder = JSONDecoder()
        if let data = defaults.data(forKey: Keys.profiles),
           let decoded = try? decoder.decode([VLESSProfile].self, from: data) {
            profiles = decoded
        } else {
            profiles = []
        }

        if let data = defaults.data(forKey: Keys.subscriptions),
           let decoded = try? decoder.decode([SubscriptionGroup].self, from: data) {
            subscriptions = decoded
        } else {
            subscriptions = []
        }

        if let data = defaults.data(forKey: Keys.settings),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }

        if let value = defaults.string(forKey: Keys.selectedProfileID),
           let id = UUID(uuidString: value),
           profiles.contains(where: { $0.id == id }) {
            selectedProfileID = id
        } else {
            selectedProfileID = profiles.first?.id
        }
    }

    var selectedProfile: VLESSProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID })
    }

    func add(_ profile: VLESSProfile = VLESSProfile()) {
        profiles.append(profile)
        selectedProfileID = profile.id
    }

    func update(_ profile: VLESSProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
    }

    func delete(_ profile: VLESSProfile) {
        profiles.removeAll(where: { $0.id == profile.id })
        if selectedProfileID == profile.id {
            selectedProfileID = profiles.first?.id
        }
    }

    func profiles(in subscription: SubscriptionGroup) -> [VLESSProfile] {
        profiles.filter { $0.subscriptionID == subscription.id }
    }

    var localProfiles: [VLESSProfile] {
        let knownIDs = Set(subscriptions.map(\.id))
        return profiles.filter { profile in
            guard let subscriptionID = profile.subscriptionID else { return true }
            return !knownIDs.contains(subscriptionID)
        }
    }

    func importURL(_ text: String) async throws {
        let imported: [VLESSProfile]
        if SubscriptionImporter.isSubscriptionLink(text) {
            imported = try await SubscriptionImporter.fetchProfiles(from: text)
            let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = subscriptions.first(where: { $0.sourceURL == source }) {
                apply(imported, to: existing.id)
            } else {
                let subscription = SubscriptionGroup(
                    name: SubscriptionImporter.subscriptionName(from: source),
                    sourceURL: source
                )
                subscriptions.append(subscription)
                apply(imported, to: subscription.id, adoptingLocalMatches: true)
            }
            return
        } else {
            imported = [try ProxyURLParser.parse(text)]
        }

        let existingKeys = Set(profiles.map(ProfileIdentity.init))
        let newProfiles = imported.filter { !existingKeys.contains(ProfileIdentity($0)) }
        profiles.append(contentsOf: newProfiles)
        selectedProfileID = newProfiles.first?.id ?? imported.first.flatMap { importedProfile in
            profiles.first(where: { ProfileIdentity($0) == ProfileIdentity(importedProfile) })?.id
        }
    }

    func renew(_ subscription: SubscriptionGroup) async throws {
        let imported = try await SubscriptionImporter.fetchProfiles(from: subscription.sourceURL)
        apply(imported, to: subscription.id)
        if let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            subscriptions[index].lastUpdated = .now
        }
    }

    func delete(_ subscription: SubscriptionGroup) {
        let removedIDs = Set(profiles(in: subscription).map(\.id))
        profiles.removeAll { $0.subscriptionID == subscription.id }
        subscriptions.removeAll { $0.id == subscription.id }
        latencyResults = latencyResults.filter { !removedIDs.contains($0.key) }
        if let selectedProfileID, removedIDs.contains(selectedProfileID) {
            self.selectedProfileID = profiles.first?.id
        }
    }

    func testLatency(for profilesToTest: [VLESSProfile]? = nil) async {
        let targets = profilesToTest ?? profiles
        guard !targets.isEmpty else { return }
        for profile in targets { latencyResults[profile.id] = .testing }

        await withTaskGroup(of: (UUID, Int?).self) { group in
            for profile in targets {
                group.addTask {
                    let result = await LatencyTester.measure(host: profile.server, port: profile.port)
                    return (profile.id, result)
                }
            }
            for await (id, milliseconds) in group {
                latencyResults[id] = milliseconds.map(LatencyStatus.reachable) ?? .unreachable
            }
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: Keys.profiles)
        }
    }

    private func saveSubscriptions() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: Keys.subscriptions)
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Keys.settings)
        }
    }

    func apply(_ imported: [VLESSProfile], to subscriptionID: UUID, adoptingLocalMatches: Bool = false) {
        let previous = profiles.filter { $0.subscriptionID == subscriptionID }
        let previousByKey = Dictionary(previous.map { (SyncIdentity($0), $0) }, uniquingKeysWith: { first, _ in first })
        let importedKeys = Set(imported.map(SyncIdentity.init))
        var replacements: [VLESSProfile] = []

        for var profile in imported {
            let key = SyncIdentity(profile)
            if let old = previousByKey[key] {
                profile.id = old.id
            } else if adoptingLocalMatches,
                      let local = profiles.first(where: { $0.subscriptionID == nil && SyncIdentity($0) == key }) {
                profile.id = local.id
            }
            profile.subscriptionID = subscriptionID
            replacements.append(profile)
        }

        let replacementIDs = Set(replacements.map(\.id))
        profiles.removeAll { profile in
            profile.subscriptionID == subscriptionID ||
                (adoptingLocalMatches && profile.subscriptionID == nil && replacementIDs.contains(profile.id))
        }
        profiles.append(contentsOf: replacements)

        let removedIDs = Set(previous.filter { !importedKeys.contains(SyncIdentity($0)) }.map(\.id))
        latencyResults = latencyResults.filter { !removedIDs.contains($0.key) }
        if let selectedProfileID, removedIDs.contains(selectedProfileID) {
            self.selectedProfileID = replacements.first?.id ?? profiles.first?.id
        } else if self.selectedProfileID == nil {
            self.selectedProfileID = replacements.first?.id
        }
    }

    private struct ProfileIdentity: Hashable {
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

    private struct SyncIdentity: Hashable {
        let server: String
        let port: Int
        let uuid: String
        let proxyProtocol: ProxyProtocol
        let credential: String

        init(_ profile: VLESSProfile) {
            server = profile.server.lowercased()
            port = profile.port
            uuid = profile.uuid.lowercased()
            proxyProtocol = profile.proxyProtocol
            credential = profile.uuid.isEmpty ? profile.password : profile.uuid.lowercased()
        }
    }
}
