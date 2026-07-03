import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var runningOperation: RunningOperation?
    @Published var lastError: String?
    @Published var diskUsage: [String: DiskUsage] = [:]
    @Published var dockerDF: [String: DockerSystemDF] = [:]
    @Published var autoStartProfiles: Set<String> = []
    @Published var updateAvailable: UpdateInfo?
    @Published private var recentlyChanged: Bool = false

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
        startPolling()
        startUpdateChecks()
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
        for profile in running {
            if let usage = try? await service.diskUsage(profileName: profile.name) {
                diskUsage[profile.name] = usage
            }
            if let df = try? await service.dockerSystemDF(profileName: profile.name) {
                dockerDF[profile.name] = df
            }
        }
        for name in diskUsage.keys where !names.contains(name) { diskUsage.removeValue(forKey: name) }
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

        let stream = makeStream(profile.name)
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await line in stream {
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
                Task { [weak self] in await self?.runAutoStart() }
            }
        } catch {
            lastError = error.localizedDescription
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

        let stream = makeStream(profile.name)
        Task { [weak self] in
            do {
                for try await line in stream {
                    op.lines.append(line)
                }
                op.state = .succeeded
                self?.lastError = nil
            } catch {
                op.state = .failed(error.localizedDescription)
                self?.lastError = error.localizedDescription
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
