import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: SingBoxService
    let profile: VLESSProfile
    let editAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                statusHeader
                profileCard
                modeCard
                connectButton

                if case .failed(let message) = service.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: 520, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 660)
            .padding(36)
            .frame(maxWidth: .infinity)
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 94, height: 94)
                Circle()
                    .stroke(statusColor.opacity(0.22), lineWidth: 1)
                    .frame(width: 78, height: 78)
                Image(systemName: service.state.isConnected ? "shield.checkered" : "shield")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(statusColor)
            }
            Text(stateTitle)
                .font(.title2.weight(.semibold))
            Text(statusSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var profileCard: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                row(L10n.t("server", model.language), "\(profile.server):\(profile.port)")
                row(L10n.t("protocol", model.language), protocolName)
                if profile.requiresTLS {
                    row(L10n.t("security", model.language), profile.security == .reality ? "Reality" : "TLS")
                    row("TLS SNI", profile.serverName)
                }
                if [.vless, .vmess, .trojan].contains(profile.proxyProtocol) {
                    row(L10n.t("transport", model.language), transportName)
                }
                if profile.proxyProtocol == .vless {
                    row("Flow", profile.flow.isEmpty ? L10n.t("none", model.language) : profile.flow)
                } else if profile.proxyProtocol == .vmess || profile.proxyProtocol == .shadowsocks {
                    row(L10n.t("encryption", model.language), profile.encryption)
                } else if profile.proxyProtocol == .hysteria2, !profile.obfuscation.isEmpty {
                    row(L10n.t("obfuscation", model.language), profile.obfuscation)
                } else if profile.proxyProtocol == .tuic {
                    row(L10n.t("congestionControl", model.language), profile.congestionControl)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        } label: {
            HStack {
                Label(profile.name, systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                Button(L10n.t("edit", model.language), action: editAction)
                    .disabled(service.state.isConnected || service.state.isBusy)
            }
        }
        .frame(maxWidth: 540)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("connectionMode", model.language)).font(.headline)
            Picker(L10n.t("connectionMode", model.language), selection: $model.settings.connectionMode) {
                ForEach(ConnectionMode.allCases) { mode in
                    Text(modeTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(service.state.isConnected || service.state.isBusy)

            Text(modeDetail(model.settings.connectionMode))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 540, alignment: .leading)
    }

    private var connectButton: some View {
        Button {
            if service.state.isConnected {
                if isCurrentProfile {
                    service.stop()
                } else {
                    service.switchProfile(to: profile, settings: model.settings)
                }
            } else {
                service.start(profile: profile, settings: model.settings)
            }
        } label: {
            HStack {
                if service.state.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: buttonIcon)
                }
                Text(buttonTitle)
            }
            .frame(minWidth: 150)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(service.state.isConnected && isCurrentProfile ? .red : .accentColor)
        .disabled(service.state.isBusy)
        .keyboardShortcut(.return, modifiers: [])
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .connected: .green
        case .connecting, .switching, .disconnecting: .orange
        case .failed: .red
        case .disconnected: .secondary
        }
    }

    private var statusSubtitle: String {
        switch service.state {
        case .connected:
            return L10n.t("trafficThrough", model.language, service.connectedProfileName ?? profile.name)
        case .connecting:
            return L10n.t("startingCore", model.language)
        case .switching:
            return L10n.t("switchingNode", model.language)
        case .disconnecting:
            return L10n.t("cleaningNetwork", model.language)
        case .failed:
            return L10n.t("checkError", model.language)
        case .disconnected:
            return L10n.t("readyToConnect", model.language)
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

    private func modeTitle(_ mode: ConnectionMode) -> String {
        L10n.t(mode == .systemProxy ? "systemProxy" : "tun", model.language)
    }

    private func modeDetail(_ mode: ConnectionMode) -> String {
        L10n.t(mode == .systemProxy ? "systemProxyDetail" : "tunDetail", model.language)
    }

    private var isCurrentProfile: Bool {
        service.connectedProfileID == profile.id
    }

    private var transportName: String {
        switch profile.transport {
        case .tcp: "TCP/raw"
        case .webSocket: "WebSocket"
        case .grpc: "gRPC"
        case .http2: "HTTP/2"
        }
    }

    private var protocolName: String {
        switch profile.proxyProtocol {
        case .vless: "VLESS"
        case .vmess: "VMess"
        case .trojan: "Trojan"
        case .shadowsocks: "Shadowsocks"
        case .hysteria2: "Hysteria2"
        case .tuic: "TUIC"
        }
    }

    private var buttonTitle: String {
        if service.state.isConnected {
            return L10n.t(isCurrentProfile ? "disconnect" : "switchToNode", model.language)
        }
        return L10n.t("connect", model.language)
    }

    private var buttonIcon: String {
        if service.state.isConnected {
            return isCurrentProfile ? "stop.fill" : "arrow.triangle.2.circlepath"
        }
        return "play.fill"
    }
}
