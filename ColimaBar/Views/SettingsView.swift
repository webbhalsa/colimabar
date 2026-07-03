import SwiftUI

private enum SidebarItem: Hashable {
    case general
    case profile(String)
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selection: SidebarItem? = .general
    @State private var showNewProfile: Bool = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("App") {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("General")
                        Spacer()
                        if appState.updateAvailable != nil {
                            Circle()
                                .fill(.red)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .tag(SidebarItem.general)
                }

                Section("Profiles") {
                    ForEach(appState.profiles) { profile in
                        HStack {
                            Circle()
                                .fill(color(for: profile.status))
                                .frame(width: 8, height: 8)
                            Text(profile.name)
                            Spacer()
                            Text(profile.status.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.profile(profile.name))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 4) {
                    Button {
                        showNewProfile = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .help("New profile")
                    .disabled(appState.runningOperation?.isRunning == true)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.bar)
            }
        } detail: {
            detailView
        }
        .frame(minWidth: 820, minHeight: 620)
        .task { await appState.refresh() }
        .onAppear { ensureSelection() }
        .onChange(of: appState.profiles) { _, _ in ensureSelection() }
        .sheet(isPresented: $showNewProfile) {
            NewProfileSheet()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .profile(let name):
            if let profile = appState.profiles.first(where: { $0.name == name }) {
                ProfileEditorView(profile: profile)
                    .id(profile.id)
            } else {
                ContentUnavailableView(
                    "Profile not found",
                    systemImage: "square.dashed",
                    description: Text("This profile no longer exists.")
                )
            }
        case .none:
            ContentUnavailableView(
                "Nothing selected",
                systemImage: "square.dashed",
                description: Text("Choose something from the sidebar.")
            )
        }
    }

    private func ensureSelection() {
        switch selection {
        case .general, .none:
            if selection == nil { selection = .general }
        case .profile(let name):
            if !appState.profiles.contains(where: { $0.name == name }) {
                let fallback = appState.profiles.first(where: { $0.status == .running })
                    ?? appState.profiles.first
                selection = fallback.map { .profile($0.name) } ?? .general
            }
        }
    }

    private func color(for status: Profile.Status) -> Color {
        switch status {
        case .running: return .green
        case .stopped: return .gray
        case .starting, .stopping: return .orange
        case .unknown: return .red
        }
    }
}

private struct ProfileEditorView: View {
    @EnvironmentObject var appState: AppState
    let profile: Profile

    @State private var draft: ProfileStartOptions
    @State private var showDeleteConfirm: Bool = false
    @Environment(\.openWindow) private var openWindow

    init(profile: Profile) {
        self.profile = profile
        _draft = State(initialValue: ProfileStartOptions(from: profile))
    }

    private var current: ProfileStartOptions { ProfileStartOptions(from: profile) }
    private var hasChanges: Bool { draft != current }
    private var isBusy: Bool { appState.runningOperation?.isRunning == true }

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("State", value: profile.status.rawValue)
                LabeledContent("Architecture", value: profile.arch)
                if !profile.address.isEmpty {
                    LabeledContent("Address", value: profile.address)
                }
                if let socket = profile.dockerSocket {
                    LabeledContent("Docker socket") {
                        Text(socket.path)
                            .textSelection(.enabled)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }

            Section("Startup") {
                Toggle("Start with ColimaBar", isOn: Binding(
                    get: { appState.autoStartProfiles.contains(profile.name) },
                    set: { appState.setAutoStart(profileName: profile.name, enabled: $0) }
                ))
                Text("When ColimaBar launches, this profile will start automatically if it's stopped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Disk usage") {
                DiskUsageRow(profileName: profile.name, isRunning: profile.status == .running)
            }

            if profile.status == .running {
                Section("Docker") {
                    DockerBreakdownRow(profile: profile)
                }
            }

            Section("Resources") {
                Stepper(value: $draft.cpu, in: 1...16) {
                    LabeledContent("CPU", value: "\(draft.cpu) cores")
                }
                Stepper(value: $draft.memoryGB, in: 1...64) {
                    LabeledContent("Memory", value: "\(draft.memoryGB) GB")
                }
                Stepper(value: $draft.diskGB, in: 20...500, step: 10) {
                    LabeledContent("Disk", value: "\(draft.diskGB) GB")
                }
                Picker("Runtime", selection: $draft.runtime) {
                    ForEach(ProfileStartOptions.runtimes, id: \.self) { rt in
                        Text(rt.capitalized).tag(rt)
                    }
                }
            }

            Section {
                if hasChanges && profile.status == .running {
                    Label("Applying will stop and restart the VM. This takes ~30 seconds.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                HStack {
                    Button("Revert") { draft = current }
                        .disabled(!hasChanges || isBusy)

                    Spacer()

                    Button(applyLabel) {
                        appState.beginApply(profile, options: draft)
                        openWindow(id: WindowID.progress.rawValue)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || isBusy)
                }
            }

            Section("Danger zone") {
                HStack(alignment: .top) {
                    Text("Deleting removes the VM, all its containers, images, volumes, and configuration. This cannot be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Delete Profile…", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .disabled(isBusy)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(profile.name)
        .confirmationDialog(
            "Delete profile \u{201C}\(profile.name)\u{201D}?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                appState.beginDelete(profileName: profile.name)
                openWindow(id: WindowID.progress.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the VM and all its data. Cannot be undone.")
        }
    }

    private var applyLabel: String {
        if isBusy { return "Applying…" }
        if hasChanges && profile.status == .running { return "Apply & Restart" }
        if hasChanges { return "Apply & Start" }
        return "Apply"
    }
}

private struct DiskUsageRow: View {
    @EnvironmentObject var appState: AppState
    let profileName: String
    let isRunning: Bool

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowedUnits = [.useGB]
        f.zeroPadsFractionDigits = false
        return f
    }()

    var body: some View {
        Group {
            if !isRunning {
                Label("Start the VM to see disk usage", systemImage: "moon.zzz")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else if let usage = appState.diskUsage[profileName] {
                usageBody(usage)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading disk usage…").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .task(id: profileName) {
            if isRunning { await appState.refreshDiskUsage() }
        }
    }

    private func usageBody(_ usage: DiskUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: usage.usedFraction)
                .tint(tint(for: usage.usedFraction))
            HStack {
                Text("\(Self.formatter.string(fromByteCount: usage.usedBytes)) used of \(Self.formatter.string(fromByteCount: usage.totalBytes)) · \(Int(usage.usedFraction * 100))%")
                Spacer()
                Text("\(Self.formatter.string(fromByteCount: usage.availableBytes)) free")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func tint(for fraction: Double) -> Color {
        if fraction >= 0.9 { return .red }
        if fraction >= 0.7 { return .orange }
        return .green
    }
}

private struct DockerBreakdownRow: View {
    @EnvironmentObject var appState: AppState
    let profile: Profile
    @Environment(\.openWindow) private var openWindow
    @State private var showDeepPruneConfirm: Bool = false

    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowedUnits = [.useGB, .useMB]
        f.zeroPadsFractionDigits = false
        return f
    }()

    private var isBusy: Bool { appState.runningOperation?.isRunning == true }

    var body: some View {
        if let df = appState.dockerDF[profile.name] {
            content(df)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading docker sizes…")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func content(_ df: DockerSystemDF) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    Text("Size")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text("Reclaimable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                ForEach(df.rows) { row in
                    GridRow {
                        HStack(spacing: 6) {
                            Text(row.type)
                            Text("(\(row.totalCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(Self.formatter.string(fromByteCount: row.sizeBytes))
                            .monospacedDigit()
                        HStack(spacing: 4) {
                            Text(Self.formatter.string(fromByteCount: row.reclaimableBytes))
                                .monospacedDigit()
                                .foregroundStyle(row.reclaimableBytes > 0 ? .orange : .secondary)
                            if row.reclaimableBytes > 0 && row.sizeBytes > 0 {
                                Text("(\(Int(Double(row.reclaimableBytes)/Double(row.sizeBytes)*100))%)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(Self.formatter.string(fromByteCount: df.safelyReclaimableBytes)) safely reclaimable")
                            .fontWeight(.semibold)
                            .foregroundStyle(df.safelyReclaimableBytes > 0 ? .orange : .secondary)
                        let deepDelta = df.totalReclaimableBytes - df.safelyReclaimableBytes
                        if deepDelta > 0 {
                            Text("· +\(Self.formatter.string(fromByteCount: deepDelta)) with deep prune")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    Text("Reclaim removes stopped containers, unused networks, dangling images, and build cache. Deep prune additionally removes tagged unused images and all unused volumes — data written only to those volumes is permanently lost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(spacing: 6) {
                    Button("Reclaim") {
                        appState.beginPrune(profile)
                        openWindow(id: WindowID.progress.rawValue)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .disabled(isBusy || df.safelyReclaimableBytes == 0)

                    Button("Deep prune…", role: .destructive) {
                        showDeepPruneConfirm = true
                    }
                    .disabled(isBusy || df.totalReclaimableBytes == 0)
                }
            }
        }
        .confirmationDialog(
            "Deep prune — permanently delete unused images and volumes?",
            isPresented: $showDeepPruneConfirm,
            titleVisibility: .visible
        ) {
            Button("Deep Prune", role: .destructive) {
                appState.beginDeepPrune(profile)
                openWindow(id: WindowID.progress.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes ALL unused images (not just dangling) and ALL unused volumes. Any data written only to those volumes is permanently lost. Running containers and volumes they are actively using are preserved.")
        }
    }
}
