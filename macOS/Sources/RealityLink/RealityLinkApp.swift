import SwiftUI

@main
struct RealityLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var service = SingBoxService()

    var body: some Scene {
        WindowGroup("RealityLink", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(service)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    appDelegate.service = service
                    service.recoverNetworkStateIfNeeded()
                }
        }
        .defaultSize(width: 980, height: 680)

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(model)
                .environmentObject(service)
        } label: {
            Image(systemName: service.state.isConnected ? "shield.fill" : "shield")
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 520)
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: SingBoxService
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(stateTitle)
        if let profile = service.connectedProfileName {
            Text(profile)
        }

        Divider()

        if service.state.isConnected || service.state == .connecting {
            if service.state == .connected,
               let profile = model.selectedProfile,
               profile.id != service.connectedProfileID {
                Button(L10n.t("switchToNamed", model.language, profile.name)) {
                    service.switchProfile(to: profile, settings: model.settings)
                }
            }
            Button(L10n.t("disconnect", model.language)) { service.stop() }
        } else if let profile = model.selectedProfile {
            Button(L10n.t("connectNamed", model.language, profile.name)) {
                service.start(profile: profile, settings: model.settings)
            }
        } else {
            Text(L10n.t("addNodeFirst", model.language))
        }

        Divider()

        Button(L10n.t("openApp", model.language)) { openWindow(id: "main") }
        Button(L10n.t(service.state.isConnected ? "disconnectQuit" : "quit", model.language)) {
            if service.state.isConnected || service.state == .connecting {
                service.stop()
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var stateTitle: String {
        let key: String
        switch service.state {
        case .disconnected: key = "disconnected"
        case .connecting: key = "connecting"
        case .connected: key = "connected"
        case .switching: key = "switching"
        case .disconnecting: key = "disconnecting"
        case .failed: key = "failed"
        }
        return L10n.t(key, model.language)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var service: SingBoxService?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let service,
              service.state.isConnected || service.state == .connecting || service.state == .disconnecting
        else {
            return .terminateNow
        }

        service.stop()
        return .terminateCancel
    }
}
