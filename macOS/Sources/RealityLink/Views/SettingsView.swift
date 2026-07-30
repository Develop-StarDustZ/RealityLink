import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section(L10n.t("language", model.language)) {
                Picker(L10n.t("language", model.language), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(L10n.t("core", model.language)) {
                TextField(L10n.t("customPath", model.language), text: $model.settings.corePath, prompt: Text(L10n.t("corePrompt", model.language)))
                Text(L10n.t("coreHelp", model.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.t("localProxy", model.language)) {
                TextField(L10n.t("listenPort", model.language), value: $model.settings.localPort, format: .number)
                Text(L10n.t("proxyHelp", model.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.t("nodeStore", model.language)) {
                Button {
                    WebsiteLinks.openNodeStore()
                } label: {
                    Label(L10n.t("buyNodes", model.language), systemImage: "cart")
                }
                Text("node.stardustz.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
