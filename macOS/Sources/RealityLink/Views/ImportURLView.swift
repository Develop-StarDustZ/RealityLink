import AppKit
import SwiftUI

struct ImportURLView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var urlText = ""
    @State private var errorMessage: String?
    @State private var isImporting = false
    let onImport: (String) async throws -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "link.badge.plus")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("importVLESS", model.language))
                        .font(.title2.weight(.semibold))
                    Text(L10n.t("importHelp", model.language))
                        .foregroundStyle(.secondary)
                }
            }

            TextEditor(text: $urlText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 140)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Button(L10n.t("pasteClipboard", model.language)) {
                    urlText = NSPasteboard.general.string(forType: .string) ?? ""
                    errorMessage = nil
                }
                Button {
                    WebsiteLinks.openNodeStore()
                } label: {
                    Label(L10n.t("buyNodes", model.language), systemImage: "cart")
                }
                .help("node.stardustz.com")
                Spacer()
                Button(L10n.t("cancel", model.language)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isImporting)
                Button {
                    Task { await importURL() }
                } label: {
                    if isImporting {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(L10n.t("importing", model.language))
                        }
                    } else {
                        Text(L10n.t("import", model.language))
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
    }

    @MainActor
    private func importURL() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            try await onImport(urlText)
            dismiss()
        } catch is CancellationError {
            return
        } catch let error as SubscriptionImportError {
            errorMessage = error.message(for: model.language)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
