import SwiftUI

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var profile: VLESSProfile
    let onSave: (VLESSProfile) -> Void

    init(profile: VLESSProfile, onSave: @escaping (VLESSProfile) -> Void) {
        _profile = State(initialValue: profile)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t(profile.server.isEmpty ? "addNode" : "editNode", model.language))
                    .font(.title2.weight(.semibold))
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section(L10n.t("basicInfo", model.language)) {
                    Picker(L10n.t("protocol", model.language), selection: $profile.proxyProtocol) {
                        ForEach(ProxyProtocol.allCases) { value in
                            Text(protocolName(value)).tag(value)
                        }
                    }
                    TextField(L10n.t("name", model.language), text: $profile.name)
                    TextField(L10n.t("server", model.language), text: $profile.server, prompt: Text("vpn.example.com"))
                    TextField(L10n.t("port", model.language), value: $profile.port, format: .number)
                    if [.vless, .vmess, .tuic].contains(profile.proxyProtocol) {
                        TextField("UUID", text: $profile.uuid)
                    }
                    if [.trojan, .shadowsocks, .hysteria2, .tuic].contains(profile.proxyProtocol) {
                        TextField(L10n.t("password", model.language), text: $profile.password)
                    }
                    if profile.proxyProtocol == .vmess {
                        Picker(L10n.t("encryption", model.language), selection: $profile.encryption) {
                            ForEach(["auto", "none", "zero", "aes-128-gcm", "chacha20-poly1305"], id: \.self) { Text($0).tag($0) }
                        }
                        TextField("Alter ID", value: $profile.alterID, format: .number)
                    } else if profile.proxyProtocol == .shadowsocks {
                        Picker(L10n.t("encryption", model.language), selection: $profile.encryption) {
                            ForEach(shadowsocksMethods, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                if profile.proxyProtocol == .vless || profile.proxyProtocol == .vmess {
                    Picker(L10n.t("security", model.language), selection: $profile.security) {
                        if profile.proxyProtocol == .vless { Text("Reality").tag(VLESSSecurity.reality) }
                        Text("TLS").tag(VLESSSecurity.tls)
                        if profile.proxyProtocol == .vmess { Text(L10n.t("none", model.language)).tag(VLESSSecurity.none) }
                    }
                }

                if supportsV2RayTransport {
                    Picker(L10n.t("transport", model.language), selection: $profile.transport) {
                        Text("TCP/raw").tag(VLESSTransport.tcp)
                        Text("WebSocket").tag(VLESSTransport.webSocket)
                        Text("gRPC").tag(VLESSTransport.grpc)
                        Text("HTTP/2").tag(VLESSTransport.http2)
                    }
                    .disabled(profile.proxyProtocol == .vless && profile.security == .reality)
                }

                if profile.requiresTLS {
                    TextField("SNI", text: $profile.serverName, prompt: Text("www.example.com"))
                    Picker("uTLS \(L10n.t("fingerprint", model.language))", selection: $profile.fingerprint) {
                        ForEach(["chrome", "safari", "firefox", "edge", "ios", "random"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    if profile.proxyProtocol == .vless && profile.security == .reality {
                        TextField(L10n.t("publicKey", model.language), text: $profile.publicKey)
                        TextField("Short ID (sid)", text: $profile.shortID)
                    } else {
                        Toggle(L10n.t("allowInsecure", model.language), isOn: $profile.allowInsecure)
                        TextField("ALPN", text: $profile.alpn, prompt: Text("h2,http/1.1"))
                    }
                    if profile.proxyProtocol == .vless && profile.transport == .tcp {
                        Picker("Flow", selection: $profile.flow) {
                            Text("xtls-rprx-vision").tag("xtls-rprx-vision")
                            Text(L10n.t("none", model.language)).tag("")
                        }
                    }
                    if supportsV2RayTransport && (profile.transport == .webSocket || profile.transport == .http2) {
                        TextField(L10n.t("transportHost", model.language), text: $profile.transportHost)
                        TextField(L10n.t("transportPath", model.language), text: $profile.transportPath, prompt: Text("/"))
                    } else if supportsV2RayTransport && profile.transport == .grpc {
                        TextField(L10n.t("serviceName", model.language), text: $profile.serviceName)
                    }
                }

                if profile.proxyProtocol == .hysteria2 {
                    Picker(L10n.t("obfuscation", model.language), selection: $profile.obfuscation) {
                        Text(L10n.t("none", model.language)).tag("")
                        Text("salamander").tag("salamander")
                    }
                    if !profile.obfuscation.isEmpty {
                        TextField(L10n.t("obfuscationPassword", model.language), text: $profile.obfuscationPassword)
                    }
                } else if profile.proxyProtocol == .tuic {
                    Picker(L10n.t("congestionControl", model.language), selection: $profile.congestionControl) {
                        ForEach(["cubic", "new_reno", "bbr"], id: \.self) { Text($0).tag($0) }
                    }
                    Picker(L10n.t("udpRelayMode", model.language), selection: $profile.udpRelayMode) {
                        ForEach(["native", "quic"], id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 4)

            Divider()

            HStack {
                Button {
                    WebsiteLinks.openNodeStore()
                } label: {
                    Label(L10n.t("buyNodes", model.language), systemImage: "cart")
                }
                .help("node.stardustz.com")

                if let message = visibleValidationMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(L10n.t("cancel", model.language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("save", model.language)) {
                    onSave(profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(profile.validationMessage != nil)
            }
            .padding(20)
        }
        .frame(width: 620, height: 680)
        .onChange(of: profile.security) { security in
            if security == .reality {
                profile.transport = .tcp
                profile.allowInsecure = false
            }
        }
        .onChange(of: profile.transport) { transport in
            if transport != .tcp { profile.flow = "" }
        }
        .onChange(of: profile.proxyProtocol) { value in
            profile.flow = ""
            profile.transport = .tcp
            switch value {
            case .vless:
                profile.security = .reality
                profile.encryption = "auto"
            case .vmess:
                profile.security = .none
                profile.encryption = "auto"
            case .trojan:
                profile.security = .tls
            case .shadowsocks:
                profile.security = .none
                profile.encryption = "aes-256-gcm"
            case .hysteria2:
                profile.security = .tls
                profile.alpn = "h3"
            case .tuic:
                profile.security = .tls
                profile.alpn = "h3"
            }
        }
    }

    private var visibleValidationMessage: String? {
        if profile.server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return profile.validationMessage
    }

    private var supportsV2RayTransport: Bool {
        [.vless, .vmess, .trojan].contains(profile.proxyProtocol)
    }

    private let shadowsocksMethods = [
        "2022-blake3-aes-128-gcm", "2022-blake3-aes-256-gcm", "2022-blake3-chacha20-poly1305",
        "aes-128-gcm", "aes-192-gcm", "aes-256-gcm", "chacha20-ietf-poly1305", "xchacha20-ietf-poly1305"
    ]

    private func protocolName(_ value: ProxyProtocol) -> String {
        switch value {
        case .vless: "VLESS"
        case .vmess: "VMess"
        case .trojan: "Trojan"
        case .shadowsocks: "Shadowsocks"
        case .hysteria2: "Hysteria2"
        case .tuic: "TUIC"
        }
    }
}
