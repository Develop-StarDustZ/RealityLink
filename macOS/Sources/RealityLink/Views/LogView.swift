import SwiftUI

struct LogView: View {
    @EnvironmentObject private var service: SingBoxService
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("runtimeLogs", model.language))
                    .font(.headline)
                Spacer()
                Button(L10n.t("clear", model.language)) { service.clearLogs() }
                    .disabled(service.logs.isEmpty)
            }
            .padding(14)

            Divider()

            if service.logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(L10n.t("noLogs", model.language))
                        .font(.headline)
                    Text(L10n.t("noLogsHelp", model.language))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(service.logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(14)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: service.logs.count) { count in
                        if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }
        }
    }
}
