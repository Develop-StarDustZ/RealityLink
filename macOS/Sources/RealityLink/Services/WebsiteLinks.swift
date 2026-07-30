import AppKit
import Foundation

enum WebsiteLinks {
    static let nodeStore = URL(string: "https://node.stardustz.com")!

    static func openNodeStore() {
        NSWorkspace.shared.open(nodeStore)
    }
}
