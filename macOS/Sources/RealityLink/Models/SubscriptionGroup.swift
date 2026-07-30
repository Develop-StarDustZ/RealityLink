import Foundation

struct SubscriptionGroup: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var sourceURL: String
    var lastUpdated: Date

    init(id: UUID = UUID(), name: String, sourceURL: String, lastUpdated: Date = .now) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.lastUpdated = lastUpdated
    }
}

enum LatencyStatus: Equatable {
    case testing
    case reachable(Int)
    case unreachable
}
