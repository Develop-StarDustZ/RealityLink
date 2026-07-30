import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: SingBoxService
    @State private var sheet: PresentedSheet?
    @State private var selectedTab = DetailTab.connection
    @State private var updatingSubscriptions = Set<UUID>()
    @State private var subscriptionError: String?
    @State private var subscriptionPendingDeletion: SubscriptionGroup?
    @State private var collapsedSubscriptionIDs = Set<UUID>()
    @State private var isLocalGroupCollapsed = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("RealityLink")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    sheet = .importURL
                } label: {
                    Label(L10n.t("importLink", model.language), systemImage: "square.and.arrow.down")
                }

                Button {
                    sheet = .add
                } label: {
                    Label(L10n.t("addNode", model.language), systemImage: "plus")
                }

                Button {
                    Task { await model.testLatency() }
                } label: {
                    Label(L10n.t("testLatency", model.language), systemImage: "speedometer")
                }
                .help(L10n.t("testLatencyHelp", model.language))
                .disabled(model.profiles.isEmpty || isTestingLatency)

                Button(action: openSettings) {
                    Label(L10n.t("settings", model.language), systemImage: "gearshape")
                }
                .help(L10n.t("settings", model.language))
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add:
                ProfileEditorView(profile: VLESSProfile()) { model.add($0) }
            case .edit(let profile):
                ProfileEditorView(profile: profile) { model.update($0) }
            case .importURL:
                ImportURLView { try await model.importURL($0) }
            }
        }
        .alert(L10n.t("subscriptionUpdateFailed", model.language), isPresented: Binding(
            get: { subscriptionError != nil },
            set: { if !$0 { subscriptionError = nil } }
        )) {
            Button(L10n.t("ok", model.language), role: .cancel) { subscriptionError = nil }
        } message: {
            Text(subscriptionError ?? "")
        }
        .confirmationDialog(
            L10n.t("deleteSubscriptionTitle", model.language),
            isPresented: Binding(
                get: { subscriptionPendingDeletion != nil },
                set: { if !$0 { subscriptionPendingDeletion = nil } }
            )
        ) {
            Button(L10n.t("deleteSubscriptionAndNodes", model.language), role: .destructive) {
                if let subscriptionPendingDeletion {
                    model.delete(subscriptionPendingDeletion)
                }
                subscriptionPendingDeletion = nil
            }
            Button(L10n.t("cancel", model.language), role: .cancel) {
                subscriptionPendingDeletion = nil
            }
        } message: {
            Text(L10n.t("deleteSubscriptionHelp", model.language))
        }
    }

    private func openSettings() {
        SettingsWindowPresenter.shared.show(model: model)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedProfileID) {
                ForEach(model.subscriptions) { subscription in
                    subscriptionGroup(subscription)
                }

                if !model.localProfiles.isEmpty {
                    localGroupHeader
                    if !isLocalGroupCollapsed {
                        ForEach(model.localProfiles) { profile in
                            profileRow(profile)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            HStack {
                Text(L10n.t("nodesCount", model.language, model.profiles.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await model.testLatency() }
                } label: {
                    if isTestingLatency {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "speedometer")
                    }
                }
                .buttonStyle(.plain)
                .help(L10n.t("testLatency", model.language))
                .disabled(model.profiles.isEmpty || isTestingLatency)
                Button {
                    sheet = .add
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.bar)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
    }

    @ViewBuilder
    private func subscriptionGroup(_ subscription: SubscriptionGroup) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    if collapsedSubscriptionIDs.contains(subscription.id) {
                        collapsedSubscriptionIDs.remove(subscription.id)
                    } else {
                        collapsedSubscriptionIDs.insert(subscription.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: collapsedSubscriptionIDs.contains(subscription.id) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22, height: 28)
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Text(subscription.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Text("\(model.profiles(in: subscription).count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if updatingSubscriptions.contains(subscription.id) {
                ProgressView().controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                Button {
                    Task { await renew(subscription) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(L10n.t("renewSubscription", model.language))
                .disabled(service.state.isConnected || service.state.isBusy)
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .contextMenu {
            Button(L10n.t("renewSubscription", model.language)) {
                Task { await renew(subscription) }
            }
            .disabled(service.state.isConnected || service.state.isBusy)
            Button(L10n.t("testGroupLatency", model.language)) {
                Task { await model.testLatency(for: model.profiles(in: subscription)) }
            }
            Button(L10n.t("deleteSubscription", model.language), role: .destructive) {
                subscriptionPendingDeletion = subscription
            }
            .disabled(service.state.isConnected || service.state.isBusy)
        }

        if !collapsedSubscriptionIDs.contains(subscription.id) {
            ForEach(model.profiles(in: subscription)) { profile in
                profileRow(profile)
            }
        }
    }

    private var localGroupHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isLocalGroupCollapsed.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isLocalGroupCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 28)
                Image(systemName: "internaldrive")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Text(L10n.t("localNodes", model.language))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("\(model.localProfiles.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func profileRow(_ profile: VLESSProfile) -> some View {
        ProfileRow(
            profile: profile,
            isActive: service.state.isConnected && service.connectedProfileID == profile.id,
            latency: model.latencyResults[profile.id]
        )
        .tag(profile.id)
        .contextMenu {
            Button(L10n.t("edit", model.language)) { sheet = .edit(profile) }
                .disabled(service.state.isConnected || service.state.isBusy || profile.subscriptionID != nil)
            Button(L10n.t("testLatency", model.language)) {
                Task { await model.testLatency(for: [profile]) }
            }
            Button(L10n.t("delete", model.language), role: .destructive) { model.delete(profile) }
                .disabled(service.state.isConnected || service.state.isBusy)
        }
    }

    @MainActor
    private func renew(_ subscription: SubscriptionGroup) async {
        updatingSubscriptions.insert(subscription.id)
        defer { updatingSubscriptions.remove(subscription.id) }
        do {
            try await model.renew(subscription)
        } catch let error as SubscriptionImportError {
            subscriptionError = error.message(for: model.language)
        } catch {
            subscriptionError = error.localizedDescription
        }
    }

    private var isTestingLatency: Bool {
        model.latencyResults.values.contains(.testing)
    }

    @ViewBuilder
    private var detail: some View {
        if let profile = model.selectedProfile {
            VStack(spacing: 0) {
                Picker(L10n.t("page", model.language), selection: $selectedTab) {
                    ForEach(DetailTab.allCases) { tab in
                        Label(tab.title(model.language), systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                .padding(.vertical, 14)

                Divider()

                switch selectedTab {
                case .connection:
                    ConnectionView(profile: profile, editAction: { sheet = .edit(profile) })
                case .logs:
                    LogView()
                }
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "network.slash")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text(L10n.t("noNodes", model.language))
                    .font(.title2.weight(.semibold))
                Text(L10n.t("noNodesHelp", model.language))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.t("importLink", model.language)) { sheet = .importURL }
                        .buttonStyle(.borderedProminent)
                    Button(L10n.t("addManually", model.language)) { sheet = .add }
                }
            }
        }
    }
}

private enum PresentedSheet: Identifiable {
    case add
    case edit(VLESSProfile)
    case importURL

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let profile): "edit-\(profile.id)"
        case .importURL: "import"
        }
    }
}

private enum DetailTab: String, CaseIterable, Identifiable {
    case connection
    case logs

    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        L10n.t(self == .connection ? "connection" : "logs", language)
    }
    var icon: String { self == .connection ? "shield" : "text.alignleft" }
}

private struct ProfileRow: View {
    let profile: VLESSProfile
    let isActive: Bool
    let latency: LatencyStatus?

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.green.opacity(0.18) : Color.accentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: isActive ? "checkmark.shield.fill" : "server.rack")
                    .foregroundStyle(isActive ? Color.green : Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).lineLimit(1)
                Text("\(profile.server):\(profile.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            LatencyBadge(status: latency)
        }
        .padding(.vertical, 3)
    }
}

private struct LatencyBadge: View {
    let status: LatencyStatus?

    var body: some View {
        Group {
            switch status {
            case .testing:
                ProgressView().controlSize(.mini)
            case .reachable(let milliseconds):
                Text("\(milliseconds) ms")
                    .foregroundStyle(color(for: milliseconds))
            case .unreachable:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case nil:
                EmptyView()
            }
        }
        .font(.caption2.monospacedDigit())
    }

    private func color(for milliseconds: Int) -> Color {
        if milliseconds < 150 { return .green }
        if milliseconds < 350 { return .orange }
        return .red
    }
}
