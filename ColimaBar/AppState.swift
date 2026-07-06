import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var runningOperation: RunningOperation?
    @Published var lastError: String?
    @Published var diskUsage: [String: DiskUsage] = [:]
    @Published var diskUsageError: [String: String] = [:]
    @Published var hostPhysicalBytes: [String: Int64] = [:]  // profile → bytes on host
    @Published var dockerDF: [String: DockerSystemDF] = [:]
    @Published var dockerImages: [String: [DockerImage]] = [:]
    @Published var dockerContainers: [String: [DockerContainer]] = [:]
    @Published var dockerVolumes: [String: [DockerVolume]] = [:]
    @Published var dockerBuildCache: [String: [DockerBuildCacheEntry]] = [:]
    @Published var dockerContainerStats: [String: [String: ContainerStats]] = [:]  // profile -> id -> stats
    @Published var dockerInfo: [String: DockerInfo] = [:]
    @Published var dockerDetailError: [String: String] = [:]
    @Published var autoStartProfiles: Set<String> = []
    @Published var updateAvailable: UpdateInfo?
    @Published var newProfileRequested: Bool = false
    @Published var colimaVersion: String?
    @Published var colimaUpdateAvailable: UpdateInfo?
    @Published var containerLogTarget: ContainerLogTarget?
    @Published var containerInspectTarget: ContainerInspectTarget?
    @Published var imageLayersTarget: ImageLayersTarget?
    @Published private var recentlyChanged: Bool = false

    struct ContainerLogTarget: Identifiable, Equatable {
        let id = UUID()
        let profileName: String
        let containerID: String
        let containerName: String
    }

    struct ContainerInspectTarget: Identifiable, Equatable {
        let id = UUID()
        let profileName: String
        let containerID: String
        let containerName: String
    }

    struct ImageLayersTarget: Identifiable, Equatable {
        let id = UUID()
        let profileName: String
        let imageID: String
        let imageDisplayName: String
        let imageSize: String
    }

    private let service = ColimaService()
    private var pollTask: Task<Void, Never>?
    private var diskPollTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var previousStatuses: [String: Profile.Status] = [:]
    private var didRunAutoStart: Bool = false
    private static let autoStartKey = "autoStartProfiles"
    private static let lastUpdateCheckKey = "lastUpdateCheckAt"
    private static let dismissedUpdateKey = "dismissedUpdateVersion"
    private static let updateCheckInterval: TimeInterval = 6 * 3600  // 6 hours

    var menuBarIconTint: NSColor {
        if let op = runningOperation, op.isRunning { return .systemOrange }
        if recentlyChanged { return .systemOrange }
        if lastError != nil && profiles.isEmpty { return .systemRed }
        if profiles.contains(where: { $0.status == .running }) { return .systemGreen }
        return .secondaryLabelColor
    }

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.autoStartKey) ?? []
        self.autoStartProfiles = Set(stored)
        AppLog.shared.log(.info, "app",
            "ColimaBar \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") starting; auto-start profiles: \(stored.sorted())")
        DiskAlerter.shared.start()
        startPolling()
        startUpdateChecks()
        Task { [weak self] in await self?.loadColimaVersion() }
    }

    private func loadColimaVersion() async {
        do {
            let version = try await service.colimaVersion()
            colimaVersion = version.isEmpty ? nil : version
            AppLog.shared.log(.info, "colima", "detected colima version \(version)")
        } catch {
            AppLog.shared.log(.error, "colima", "could not read colima version: \(error.localizedDescription)")
            return
        }
        guard let version = colimaVersion else { return }
        if let info = await UpdateChecker.fetchLatestColima(current: version) {
            colimaUpdateAvailable = info
            AppLog.shared.log(.info, "colima", "update available: \(info.currentVersion) → \(info.latestVersion)")
        }
    }

    func openContainerShell(profileName: String, containerID: String, containerName: String) {
        let safeName = containerName.replacingOccurrences(of: "/", with: "_")
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("colimabar-exec-\(profileName)-\(safeName).command")
        // Prefer bash if the container has it, fall back to sh — most images
        // ship sh, some also ship bash.
        let script = """
        #!/bin/bash
        exec \(service.binary) ssh -p \(profileName) -- docker exec -it \(containerID) sh -c 'command -v bash > /dev/null && exec bash || exec sh'
        """
        do {
            try script.write(to: tempURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempURL.path)
            NSWorkspace.shared.open(tempURL)
            AppLog.shared.log(.info, "container", "opened shell in \(containerName) (\(String(containerID.prefix(12))))")
        } catch {
            lastError = "Could not open container shell: \(error.localizedDescription)"
            AppLog.shared.log(.error, "container", "shell into \(containerID.prefix(12)) failed: \(error.localizedDescription)")
        }
    }

    func openTerminalInVM(profileName: String) {
        // .command files open in a new Terminal window on double-click / `open`
        // and execute their contents. This avoids needing Automation permission
        // for AppleScript'ing Terminal, which was silently failing.
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("colimabar-ssh-\(profileName).command")
        let script = "#!/bin/bash\nexec \(service.binary) ssh -p \(profileName)\n"
        do {
            try script.write(to: tempURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: tempURL.path
            )
            NSWorkspace.shared.open(tempURL)
        } catch {
            lastError = "Could not open Terminal: \(error.localizedDescription)"
        }
    }

    func startContainer(profileName: String, containerID: String) async {
        do {
            _ = try await service.startContainer(profileName: profileName, containerID: containerID)
            await loadDockerContainers(profileName: profileName)
        } catch {
            dockerDetailError["\(profileName)/containers"] = error.localizedDescription
        }
    }

    func stopContainer(profileName: String, containerID: String) async {
        do {
            _ = try await service.stopContainer(profileName: profileName, containerID: containerID)
            await loadDockerContainers(profileName: profileName)
        } catch {
            dockerDetailError["\(profileName)/containers"] = error.localizedDescription
        }
    }

    func restartContainer(profileName: String, containerID: String) async {
        do {
            _ = try await service.restartContainer(profileName: profileName, containerID: containerID)
            await loadDockerContainers(profileName: profileName)
            AppLog.shared.log(.info, "container", "restarted \(containerID.prefix(12)) in \(profileName)")
        } catch {
            dockerDetailError["\(profileName)/containers"] = error.localizedDescription
            AppLog.shared.log(.error, "container", "restart \(containerID.prefix(12)) failed: \(error.localizedDescription)")
        }
    }

    func openContainerLogs(profile: String, containerID: String, name: String) {
        containerLogTarget = ContainerLogTarget(profileName: profile, containerID: containerID, containerName: name)
    }

    func openContainerInspect(profile: String, containerID: String, name: String) {
        containerInspectTarget = ContainerInspectTarget(profileName: profile, containerID: containerID, containerName: name)
    }

    func openImageLayers(profile: String, imageID: String, displayName: String, size: String) {
        imageLayersTarget = ImageLayersTarget(profileName: profile, imageID: imageID, imageDisplayName: displayName, imageSize: size)
    }

    private func startUpdateChecks() {
        updateCheckTask?.cancel()
        updateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdateIfNeeded()
                try? await Task.sleep(for: .seconds(Self.updateCheckInterval))
            }
        }
    }

    private func checkForUpdateIfNeeded() async {
        let last = UserDefaults.standard.object(forKey: Self.lastUpdateCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) < Self.updateCheckInterval { return }
        UserDefaults.standard.set(Date(), forKey: Self.lastUpdateCheckKey)

        guard let info = await UpdateChecker.fetchLatest() else { return }
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedUpdateKey)
        guard info.latestVersion != dismissed else { return }
        updateAvailable = info
    }

    func dismissUpdate() {
        guard let info = updateAvailable else { return }
        UserDefaults.standard.set(info.latestVersion, forKey: Self.dismissedUpdateKey)
        updateAvailable = nil
    }

    func setAutoStart(profileName: String, enabled: Bool) {
        if enabled {
            autoStartProfiles.insert(profileName)
        } else {
            autoStartProfiles.remove(profileName)
        }
        UserDefaults.standard.set(Array(autoStartProfiles).sorted(), forKey: Self.autoStartKey)
    }

    private func runAutoStart() async {
        for name in autoStartProfiles.sorted() {
            while runningOperation?.isRunning == true {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let profile = profiles.first(where: { $0.name == name }),
                  profile.status == .stopped else { continue }
            beginStart(profile)
            while runningOperation?.isRunning == true {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        diskPollTask?.cancel()
        diskPollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshDiskUsage()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func refreshDiskUsage() async {
        let running = profiles.filter { $0.status == .running }
        let names = Set(profiles.map { $0.name })
        // Host physical size can be measured whether the VM is running or not,
        // so refresh for every profile (running or stopped).
        for profile in profiles {
            if let bytes = await service.hostPhysicalBytes(profileName: profile.name) {
                hostPhysicalBytes[profile.name] = bytes
            }
        }
        for name in hostPhysicalBytes.keys where !names.contains(name) {
            hostPhysicalBytes.removeValue(forKey: name)
        }
        for profile in running {
            do {
                let usage = try await service.diskUsage(profileName: profile.name, runtime: profile.runtime)
                diskUsage[profile.name] = usage
                diskUsageError.removeValue(forKey: profile.name)
                AppLog.shared.log(.debug, "disk",
                    "\(profile.name): \(usage.usedBytes / 1_000_000_000)/\(usage.totalBytes / 1_000_000_000) GB used (\(Int(usage.usedFraction * 100))%)")
                DiskAlerter.shared.evaluate(usage, profileName: profile.name)
            } catch {
                diskUsageError[profile.name] = error.localizedDescription
                AppLog.shared.log(.error, "disk",
                    "\(profile.name): \(error.localizedDescription)")
            }
            if profile.runtime.lowercased() == "docker" {
                do {
                    let df = try await service.dockerSystemDF(profileName: profile.name)
                    dockerDF[profile.name] = df
                    AppLog.shared.log(.debug, "docker-df",
                        "\(profile.name): \(df.rows.count) categories")
                } catch {
                    AppLog.shared.log(.error, "docker-df",
                        "\(profile.name): \(error.localizedDescription)")
                }
            } else {
                dockerDF.removeValue(forKey: profile.name)
            }
        }
        for name in diskUsage.keys where !names.contains(name) { diskUsage.removeValue(forKey: name) }
        for name in diskUsageError.keys where !names.contains(name) { diskUsageError.removeValue(forKey: name) }
        for name in dockerDF.keys where !names.contains(name) { dockerDF.removeValue(forKey: name) }
    }

    func beginCreate(name: String, options: ProfileStartOptions) {
        if let op = runningOperation, op.isRunning { return }

        let op = RunningOperation(profileName: name, action: "Create")
        runningOperation = op

        Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in self.service.startWith(profileName: name, options: options) {
                    op.lines.append(line)
                }
                op.state = .succeeded
                self.lastError = nil
            } catch {
                op.state = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
            await self.refresh()
            await self.refreshDiskUsage()
        }
    }

    func beginDelete(profileName: String) {
        if let op = runningOperation, op.isRunning { return }

        let op = RunningOperation(profileName: profileName, action: "Delete")
        runningOperation = op

        Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in self.service.delete(profileName: profileName) {
                    op.lines.append(line)
                }
                op.state = .succeeded
                self.lastError = nil
            } catch {
                op.state = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
            await self.refresh()
        }
    }

    // MARK: - Docker detail (lazy)

    func loadDockerImages(profileName: String) async {
        do {
            dockerImages[profileName] = try await service.dockerImages(profileName: profileName)
            dockerDetailError.removeValue(forKey: "\(profileName)/images")
        } catch {
            dockerDetailError["\(profileName)/images"] = error.localizedDescription
        }
    }

    func loadDockerContainers(profileName: String) async {
        do {
            dockerContainers[profileName] = try await service.dockerContainers(profileName: profileName)
            dockerDetailError.removeValue(forKey: "\(profileName)/containers")
        } catch {
            dockerDetailError["\(profileName)/containers"] = error.localizedDescription
        }
    }

    func loadContainerStats(profileName: String) async {
        guard let stats = try? await service.dockerStats(profileName: profileName) else { return }
        var byID: [String: ContainerStats] = [:]
        for stat in stats { byID[stat.containerID] = stat }
        dockerContainerStats[profileName] = byID
    }

    func copyDockerHost(for profile: Profile) {
        guard let socket = profile.dockerSocket else { return }
        let command = "export DOCKER_HOST=unix://\(socket.path)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    func loadDockerBuildCache(profileName: String) async {
        do {
            dockerBuildCache[profileName] = try await service.dockerBuildCache(profileName: profileName)
            dockerDetailError.removeValue(forKey: "\(profileName)/buildcache")
        } catch {
            dockerDetailError["\(profileName)/buildcache"] = error.localizedDescription
        }
    }

    func loadDockerVolumes(profileName: String) async {
        do {
            dockerVolumes[profileName] = try await service.dockerVolumes(profileName: profileName)
            dockerDetailError.removeValue(forKey: "\(profileName)/volumes")
        } catch {
            dockerDetailError["\(profileName)/volumes"] = error.localizedDescription
        }
    }

    func loadDockerInfo(profileName: String) async {
        do {
            dockerInfo[profileName] = try await service.dockerInfo(profileName: profileName)
            dockerDetailError.removeValue(forKey: "\(profileName)/info")
        } catch {
            dockerDetailError["\(profileName)/info"] = error.localizedDescription
        }
    }

    func colimaConfigURL(profileName: String) -> URL {
        URL(fileURLWithPath: ("~/.colima/\(profileName)/colima.yaml" as NSString).expandingTildeInPath)
    }

    func colimaConfigContents(profileName: String) -> String? {
        try? String(contentsOf: colimaConfigURL(profileName: profileName), encoding: .utf8)
    }

    func removeDockerImage(profileName: String, imageID: String) async {
        do {
            _ = try await service.removeDockerImage(profileName: profileName, imageID: imageID)
            await loadDockerImages(profileName: profileName)
            await refreshDiskUsage()
        } catch {
            dockerDetailError["\(profileName)/images"] = error.localizedDescription
        }
    }

    func removeDockerContainer(profileName: String, containerID: String) async {
        do {
            _ = try await service.removeDockerContainer(profileName: profileName, containerID: containerID)
            await loadDockerContainers(profileName: profileName)
            await refreshDiskUsage()
        } catch {
            dockerDetailError["\(profileName)/containers"] = error.localizedDescription
        }
    }

    func removeDockerVolume(profileName: String, name: String) async {
        do {
            _ = try await service.removeDockerVolume(profileName: profileName, name: name)
            await loadDockerVolumes(profileName: profileName)
            await refreshDiskUsage()
        } catch {
            dockerDetailError["\(profileName)/volumes"] = error.localizedDescription
        }
    }

    // MARK: - Actions

    func beginPrune(_ profile: Profile) {
        runPrune(profile: profile, action: "Prune") { service.dockerPrune(profileName: $0) }
    }

    func beginDeepPrune(_ profile: Profile) {
        runPrune(profile: profile, action: "Deep prune") { service.dockerDeepPrune(profileName: $0) }
    }

    private func runPrune(
        profile: Profile,
        action: String,
        _ makeStream: (String) -> AsyncThrowingStream<String, Error>
    ) {
        if let op = runningOperation, op.isRunning { return }

        let op = RunningOperation(profileName: profile.name, action: action)
        runningOperation = op
        AppLog.shared.log(.info, "prune", "\(action) \(profile.name) — begin")

        let stream = makeStream(profile.name)
        let profileName = profile.name
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in stream {
                    op.lines.append(line)
                }
                op.state = .succeeded
                self.lastError = nil
                AppLog.shared.log(.info, "prune",
                    "\(action) \(profileName) — succeeded (\(op.lines.count) lines)")
            } catch {
                op.state = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
                AppLog.shared.log(.error, "prune",
                    "\(action) \(profileName) — failed: \(error.localizedDescription)")
            }
            self.dockerImages.removeValue(forKey: profileName)
            self.dockerContainers.removeValue(forKey: profileName)
            self.dockerVolumes.removeValue(forKey: profileName)
            self.dockerBuildCache.removeValue(forKey: profileName)
            await self.refresh()
            await self.refreshDiskUsage()
        }
    }

    func refresh() async {
        do {
            let newProfiles = try await service.list()
            let newStatuses = Dictionary(uniqueKeysWithValues: newProfiles.map { ($0.name, $0.status) })

            var transitioned = false
            for (name, newStatus) in newStatuses {
                if let old = previousStatuses[name], old != newStatus {
                    transitioned = true
                    break
                }
            }

            previousStatuses = newStatuses
            profiles = newProfiles
            lastError = nil

            if transitioned && runningOperation?.isRunning != true {
                flashTransition()
            }

            if !didRunAutoStart {
                didRunAutoStart = true
                let toStart = autoStartProfiles.intersection(profiles.filter { $0.status == .stopped }.map { $0.name })
                if !toStart.isEmpty {
                    AppLog.shared.log(.info, "auto-start", "will start: \(toStart.sorted())")
                }
                Task { [weak self] in await self?.runAutoStart() }
            }

            AppLog.shared.log(.debug, "poll",
                "\(newProfiles.count) profile(s), \(newProfiles.filter { $0.status == .running }.count) running\(transitioned ? " — state changed" : "")")
        } catch {
            lastError = error.localizedDescription
            AppLog.shared.log(.error, "poll", "colima list failed: \(error.localizedDescription)")
        }
    }

    func beginStart(_ profile: Profile) {
        perform(action: "Start", profile: profile) { service.start(profileName: $0) }
    }

    func beginStop(_ profile: Profile) {
        perform(action: "Stop", profile: profile) { service.stop(profileName: $0) }
    }

    func beginRestart(_ profile: Profile) {
        perform(action: "Restart", profile: profile) { service.restart(profileName: $0) }
    }

    func beginApply(_ profile: Profile, options: ProfileStartOptions) {
        if let op = runningOperation, op.isRunning { return }

        let op = RunningOperation(profileName: profile.name, action: "Apply")
        runningOperation = op

        let needsStop = profile.status == .running

        Task { [weak self] in
            guard let self else { return }
            do {
                if needsStop {
                    op.lines.append("— stopping —")
                    for try await line in self.service.stop(profileName: profile.name) {
                        op.lines.append(line)
                    }
                }
                op.lines.append("— starting with new config —")
                for try await line in self.service.startWith(profileName: profile.name, options: options) {
                    op.lines.append(line)
                }
                op.state = .succeeded
                self.lastError = nil
            } catch {
                op.state = .failed(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
            await self.refresh()
        }
    }

    private func perform(
        action: String,
        profile: Profile,
        _ makeStream: (String) -> AsyncThrowingStream<String, Error>
    ) {
        if let op = runningOperation, op.isRunning { return }

        let op = RunningOperation(profileName: profile.name, action: action)
        runningOperation = op
        AppLog.shared.log(.info, "action", "\(action) \(profile.name) — begin")

        let stream = makeStream(profile.name)
        Task { [weak self] in
            do {
                for try await line in stream {
                    op.lines.append(line)
                }
                op.state = .succeeded
                self?.lastError = nil
                AppLog.shared.log(.info, "action",
                    "\(action) \(profile.name) — succeeded (\(op.lines.count) lines)")
            } catch {
                op.state = .failed(error.localizedDescription)
                self?.lastError = error.localizedDescription
                AppLog.shared.log(.error, "action",
                    "\(action) \(profile.name) — failed: \(error.localizedDescription)")
            }
            await self?.refresh()
        }
    }

    private func flashTransition() {
        flashTask?.cancel()
        recentlyChanged = true
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.recentlyChanged = false
        }
    }
}
