import SwiftUI

private enum SidebarItem: Hashable {
    case general
    case profile(String)
}

private struct HoverIconStyle: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovering ? Color.primary.opacity(0.12) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 4))
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

extension View {
    fileprivate func hoverIconStyle() -> some View { modifier(HoverIconStyle()) }
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
                    }
                    .buttonStyle(.borderless)
                    .hoverIconStyle()
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
        .frame(minWidth: 820, idealWidth: 900, maxWidth: .infinity,
               minHeight: 620, idealHeight: 700, maxHeight: .infinity)
        .task { await appState.refresh() }
        .onAppear { ensureSelection() }
        .onChange(of: appState.profiles) { _, _ in ensureSelection() }
        .sheet(isPresented: $showNewProfile) {
            NewProfileSheet()
                .environmentObject(appState)
        }
        .onChange(of: appState.newProfileRequested) { _, requested in
            if requested {
                showNewProfile = true
                appState.newProfileRequested = false
            }
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
                        HStack(spacing: 6) {
                            Text(socket.path)
                                .textSelection(.enabled)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button {
                                appState.copyDockerHost(for: profile)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .hoverIconStyle()
                            .help("Copy `export DOCKER_HOST=unix://…` to clipboard")
                        }
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
                if profile.runtime.lowercased() == "docker" {
                    Section("Docker") {
                        DockerBreakdownRow(profile: profile)
                    }
                    Section("Docker daemon") {
                        DockerDaemonInfoRow(profileName: profile.name)
                    }
                } else {
                    Section("Docker") {
                        Label("This profile uses the \(profile.runtime) runtime — Docker-specific views are hidden.",
                              systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
            } else if let err = appState.diskUsageError[profileName] {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack(spacing: 0) {
                Spacer()
                Text("Size")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Text("Unused")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .trailing)
            }
            .padding(.leading, 24)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(df.rows) { row in
                    DisclosureGroup {
                        detailContent(for: row)
                            .padding(.leading, 4)
                            .padding(.vertical, 4)
                    } label: {
                        summaryLabel(for: row)
                    }
                }
            }

            Divider()

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Label {
                            Text("Reclaim: ") +
                            Text(Self.formatter.string(fromByteCount: df.safelyReclaimableBytes))
                                .fontWeight(.semibold)
                                .foregroundColor(df.safelyReclaimableBytes > 0 ? .orange : .secondary)
                        } icon: {
                            EmptyView()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Label {
                            Text("Deep prune: ") +
                            Text(Self.formatter.string(fromByteCount: df.totalReclaimableBytes))
                                .fontWeight(.semibold)
                                .foregroundColor(df.totalReclaimableBytes > 0 ? .red : .secondary)
                        } icon: {
                            EmptyView()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    .disabled(isBusy)

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

    @ViewBuilder
    private func summaryLabel(for row: DockerSystemDF.Row) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(row.type)
                Text("(\(row.totalCount))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Self.formatter.string(fromByteCount: row.sizeBytes))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            HStack(spacing: 4) {
                Text(Self.formatter.string(fromByteCount: row.reclaimableBytes))
                    .monospacedDigit()
                    .foregroundStyle(row.reclaimableBytes > 0 ? .orange : .secondary)
                if row.reclaimableBytes > 0 && row.sizeBytes > 0 {
                    Text("(\(Int(Double(row.reclaimableBytes)/Double(row.sizeBytes) * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 130, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func detailContent(for row: DockerSystemDF.Row) -> some View {
        switch row.type {
        case "Images":
            DockerImagesList(profileName: profile.name)
        case "Containers":
            DockerContainersList(profileName: profile.name)
        case "Local Volumes":
            DockerVolumesList(profileName: profile.name)
        default:
            Text("Per-item detail not available — Reclaim clears all entries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DockerImagesList: View {
    @EnvironmentObject var appState: AppState
    let profileName: String
    @State private var pendingRemoval: String?

    var body: some View {
        Group {
            if let items = appState.dockerImages[profileName] {
                if items.isEmpty {
                    Text("No images.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 3) {
                        ForEach(items) { image in row(image) }
                    }
                }
            } else if let err = appState.dockerDetailError["\(profileName)/images"] {
                Text(err).foregroundStyle(.red).font(.caption)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading images…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { await appState.loadDockerImages(profileName: profileName) }
    }

    private func row(_ image: DockerImage) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(image.displayName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("\(image.imageID.prefix(12)) · \(image.createdSince)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(image.size).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Button {
                pendingRemoval = image.imageID
                Task {
                    await appState.removeDockerImage(profileName: profileName, imageID: image.imageID)
                    pendingRemoval = nil
                }
            } label: {
                if pendingRemoval == image.imageID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .disabled(pendingRemoval != nil)
            .help("Remove image")
        }
        .padding(.vertical, 2)
    }
}

private struct DockerContainersList: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    let profileName: String
    @State private var pendingRemoval: String?
    @State private var pendingAction: String?

    var body: some View {
        Group {
            if let items = appState.dockerContainers[profileName] {
                if items.isEmpty {
                    Text("No containers.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 3) {
                        ForEach(items) { container in row(container) }
                    }
                }
            } else if let err = appState.dockerDetailError["\(profileName)/containers"] {
                Text(err).foregroundStyle(.red).font(.caption)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading containers…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { await appState.loadDockerContainers(profileName: profileName) }
        .task(id: profileName) {
            while !Task.isCancelled {
                await appState.loadContainerStats(profileName: profileName)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func row(_ c: DockerContainer) -> some View {
        let stats = appState.dockerContainerStats[profileName]?[String(c.containerID.prefix(12))]
            ?? appState.dockerContainerStats[profileName]?[c.containerID]
        let publishedPorts = c.ports.filter(\.isPublished)
        return HStack(spacing: 8) {
            Circle()
                .fill(c.state.lowercased() == "running" ? .green : .gray)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    Text(c.image).lineLimit(1).truncationMode(.middle)
                    Text("·")
                    Text(c.status).lineLimit(1).truncationMode(.tail)
                    if let stats {
                        Text("·")
                        Text("CPU \(stats.cpuPercent)").monospacedDigit()
                        Text("·")
                        Text("Mem \(stats.memPercent)").monospacedDigit()
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
                if !publishedPorts.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(publishedPorts) { port in
                            PortPill(port: port)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Text(c.size).font(.caption).monospacedDigit().foregroundStyle(.secondary)

            Button {
                pendingAction = c.containerID
                Task {
                    if c.state.lowercased() == "running" {
                        await appState.stopContainer(profileName: profileName, containerID: c.containerID)
                    } else {
                        await appState.startContainer(profileName: profileName, containerID: c.containerID)
                    }
                    pendingAction = nil
                }
            } label: {
                if pendingAction == c.containerID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: c.state.lowercased() == "running" ? "stop.fill" : "play.fill")
                }
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .disabled(pendingAction != nil || pendingRemoval != nil)
            .help(c.state.lowercased() == "running" ? "Stop container" : "Start container")

            Button {
                pendingAction = c.containerID
                Task {
                    await appState.restartContainer(profileName: profileName, containerID: c.containerID)
                    pendingAction = nil
                }
            } label: {
                if pendingAction == c.containerID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .disabled(pendingAction != nil || pendingRemoval != nil)
            .help("Restart container")

            Button {
                appState.openContainerShell(profileName: profileName, containerID: c.containerID, containerName: c.name)
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .disabled(c.state.lowercased() != "running")
            .help("Open shell in container")

            Button {
                appState.openContainerLogs(profile: profileName, containerID: c.containerID, name: c.name)
                openWindow(id: WindowID.containerLogs.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "text.alignleft")
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .help("Show container logs")

            Button {
                appState.openContainerInspect(profile: profileName, containerID: c.containerID, name: c.name)
                openWindow(id: WindowID.containerInspect.rawValue)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .help("Inspect container (docker inspect)")

            Button {
                pendingRemoval = c.containerID
                Task {
                    await appState.removeDockerContainer(profileName: profileName, containerID: c.containerID)
                    pendingRemoval = nil
                }
            } label: {
                if pendingRemoval == c.containerID {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .disabled(pendingRemoval != nil)
            .help("Force-remove container (stops it first if running)")
        }
        .padding(.vertical, 2)
    }
}

private struct DockerDaemonInfoRow: View {
    @EnvironmentObject var appState: AppState
    let profileName: String

    private static let memFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useGB, .useMB]
        return f
    }()

    var body: some View {
        Group {
            if let info = appState.dockerInfo[profileName] {
                content(info)
            } else if let err = appState.dockerDetailError["\(profileName)/info"] {
                Text(err).foregroundStyle(.red).font(.caption)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading docker info…").foregroundStyle(.secondary).font(.caption)
                }
            }
        }
        .task { await appState.loadDockerInfo(profileName: profileName) }
    }

    @ViewBuilder
    private func content(_ info: DockerInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Server version", info.serverVersion)
            row("Storage driver", info.storageDriver)
            row("Cgroup driver", info.cgroupDriver)
            row("Logging driver", info.loggingDriver)
            row("Docker root dir", info.dockerRootDir, monospaced: true)
            row("Kernel / OS", "\(info.kernelVersion) · \(info.operatingSystem)")
            row("Architecture", info.architecture)
            row("CPUs / Memory", "\(info.cpuCount) · \(Self.memFormatter.string(fromByteCount: info.totalMemory))")
            if !info.insecureRegistries.isEmpty {
                row("Insecure registries", info.insecureRegistries.joined(separator: ", "))
            }
            if !info.registryMirrors.isEmpty {
                row("Registry mirrors", info.registryMirrors.joined(separator: ", "))
            }
        }
    }

    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PortPill: View {
    let port: DockerContainer.PortMapping
    @State private var justCopied = false
    @State private var isHovering = false

    var body: some View {
        Button(action: copyPort) {
            HStack(spacing: 3) {
                Image(systemName: iconName)
                    .font(.system(size: 9))
                Text("\(port.hostPort)")
                    .font(.system(.caption2, design: .monospaced))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(
                    justCopied
                        ? Color.green.opacity(0.25)
                        : (isHovering ? Color.gray.opacity(0.28) : Color.gray.opacity(0.18))
                )
            )
        }
        .buttonStyle(.plain)
        .help("Click to copy \(port.hostPort) · right-click for more · maps to \(port.containerPort)/\(port.proto)")
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .contextMenu {
            Button("Copy port \(port.hostPort)") { copyPort() }
            if let url = port.httpURL {
                Button("Copy URL \(url.absoluteString)") { copyURL(url) }
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
            }
        }
    }

    private var iconName: String {
        if justCopied { return "checkmark" }
        return port.isLikelyHTTP ? "network" : "doc.on.doc"
    }

    private func copyPort() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(port.hostPort)", forType: .string)
        flash()
    }

    private func copyURL(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        flash()
    }

    private func flash() {
        justCopied = true
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            justCopied = false
        }
    }
}

private struct DockerVolumesList: View {
    @EnvironmentObject var appState: AppState
    let profileName: String
    @State private var pendingRemoval: String?
    @State private var confirmingVolume: DockerVolume?

    var body: some View {
        Group {
            if let items = appState.dockerVolumes[profileName] {
                if items.isEmpty {
                    Text("No volumes.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 3) {
                        ForEach(items) { volume in row(volume) }
                    }
                }
            } else if let err = appState.dockerDetailError["\(profileName)/volumes"] {
                Text(err).foregroundStyle(.red).font(.caption)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading volumes…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task { await appState.loadDockerVolumes(profileName: profileName) }
        .confirmationDialog(
            confirmingVolume.map { "Remove volume \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: Binding(
                get: { confirmingVolume != nil },
                set: { if !$0 { confirmingVolume = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingVolume
        ) { volume in
            Button("Remove", role: .destructive) {
                pendingRemoval = volume.name
                Task {
                    await appState.removeDockerVolume(profileName: profileName, name: volume.name)
                    pendingRemoval = nil
                }
                confirmingVolume = nil
            }
            Button("Cancel", role: .cancel) { confirmingVolume = nil }
        } message: { _ in
            Text("Any data stored in this volume will be permanently deleted.")
        }
    }

    private func row(_ v: DockerVolume) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(v.name)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(v.mountpoint)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            Button {
                confirmingVolume = v
            } label: {
                if pendingRemoval == v.name {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "trash")
                }
            }
            .buttonStyle(.borderless)
            .hoverIconStyle()
            .disabled(pendingRemoval != nil)
            .help("Remove volume")
        }
        .padding(.vertical, 2)
    }
}
