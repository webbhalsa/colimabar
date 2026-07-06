import Foundation

struct ColimaService {
    enum ColimaError: LocalizedError {
        case binaryNotFound
        case commandFailed(exitCode: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return "colima binary not found. Install with: brew install colima"
            case .commandFailed(let code, let message):
                return message.isEmpty
                    ? "colima exited with code \(code)"
                    : "colima exited with code \(code): \(message)"
            }
        }
    }

    private let binaryPath: String

    init() {
        let candidates = [
            "/opt/homebrew/bin/colima",
            "/usr/local/bin/colima",
            "/opt/local/bin/colima",
        ]
        self.binaryPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "colima"
    }

    func list() async throws -> [Profile] {
        let output = try await runOnce(["list", "--json"])
        return output
            .split(separator: "\n")
            .compactMap { line -> Profile? in
                guard let data = line.data(using: .utf8),
                      let raw = try? JSONDecoder().decode(RawProfile.self, from: data)
                else { return nil }
                return raw.toProfile()
            }
    }

    func start(profileName: String) -> AsyncThrowingStream<String, Error> {
        stream(["start", profileName])
    }

    func startWith(profileName: String, options: ProfileStartOptions) -> AsyncThrowingStream<String, Error> {
        stream(["start", profileName] + options.colimaArgs)
    }

    func diskUsage(profileName: String, runtime: String) async throws -> DiskUsage {
        // Measure the filesystem backing the runtime's data root. Whatever
        // mount that is (dedicated data disk or VM root) is what fills up.
        let path: String
        switch runtime.lowercased() {
        case "containerd": path = "/var/lib/containerd"
        case "incus":      path = "/var/lib/incus"
        default:           path = "/var/lib/docker"
        }
        let output = try await runOnce(["ssh", "-p", profileName, "--", "df", "-k", path])
        guard let usage = DiskUsage.parse(dfOutput: output, sampledAt: Date()) else {
            throw ColimaError.commandFailed(
                exitCode: -1,
                message: "Could not parse df output: \(output.prefix(200))"
            )
        }
        return usage
    }

    func dockerInfo(profileName: String) async throws -> DockerInfo {
        let output = try await runOnce([
            "ssh", "-p", profileName, "--",
            "docker", "info", "--format", "{{json .}}"
        ])
        guard let info = DockerInfo.parse(output) else {
            throw ColimaError.commandFailed(exitCode: -1, message: "Could not parse docker info output")
        }
        return info
    }

    func dockerSystemDF(profileName: String) async throws -> DockerSystemDF {
        let output = try await runOnce(["ssh", "-p", profileName, "--", "docker", "system", "df", "--format", "{{json .}}"])
        guard let df = DockerSystemDF.parse(output, sampledAt: Date()) else {
            throw ColimaError.commandFailed(
                exitCode: -1,
                message: "Could not parse docker system df output"
            )
        }
        return df
    }

    func dockerPrune(profileName: String) -> AsyncThrowingStream<String, Error> {
        stream(["ssh", "-p", profileName, "--", "docker", "system", "prune", "-f"])
    }

    func dockerDeepPrune(profileName: String) -> AsyncThrowingStream<String, Error> {
        stream(["ssh", "-p", profileName, "--", "docker", "system", "prune", "-a", "--volumes", "-f"])
    }

    func dockerImages(profileName: String) async throws -> [DockerImage] {
        let output = try await runOnce(["ssh", "-p", profileName, "--", "docker", "image", "ls", "-a", "--format", "{{json .}}"])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawImage.self, from: data)
            else { return nil }
            return DockerImage(
                imageID: raw.id,
                repository: raw.repository,
                tag: raw.tag,
                size: raw.size,
                createdSince: raw.createdSince
            )
        }
    }

    func dockerContainers(profileName: String) async throws -> [DockerContainer] {
        let output = try await runOnce(["ssh", "-p", profileName, "--", "docker", "ps", "-a", "--format", "{{json .}}"])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawContainer.self, from: data)
            else { return nil }
            return DockerContainer(
                containerID: raw.id,
                name: raw.names,
                image: raw.image,
                state: raw.state,
                status: raw.status,
                size: raw.size,
                ports: DockerContainer.PortMapping.parseList(raw.ports)
            )
        }
    }

    func dockerStats(profileName: String) async throws -> [ContainerStats] {
        let output = try await runOnce([
            "ssh", "-p", profileName, "--",
            "docker", "stats", "--no-stream", "--format", "{{json .}}"
        ])
        return output.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { ContainerStats.parse(String($0)) }
    }

    func dockerBuildCache(profileName: String) async throws -> [DockerBuildCacheEntry] {
        let output = try await runOnce([
            "ssh", "-p", profileName, "--",
            "docker", "builder", "du", "--verbose"
        ])
        return DockerBuildCacheEntry.parseVerbose(output)
    }

    func dockerVolumes(profileName: String) async throws -> [DockerVolume] {
        let output = try await runOnce(["ssh", "-p", profileName, "--", "docker", "volume", "ls", "--format", "{{json .}}"])
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawVolume.self, from: data)
            else { return nil }
            return DockerVolume(
                name: raw.name,
                driver: raw.driver,
                mountpoint: raw.mountpoint,
                links: raw.links
            )
        }
    }

    func removeDockerImage(profileName: String, imageID: String) async throws -> String {
        try await runOnce(["ssh", "-p", profileName, "--", "docker", "image", "rm", imageID])
    }

    func removeDockerContainer(profileName: String, containerID: String) async throws -> String {
        try await runOnce(["ssh", "-p", profileName, "--", "docker", "rm", "-f", containerID])
    }

    func removeDockerVolume(profileName: String, name: String) async throws -> String {
        try await runOnce(["ssh", "-p", profileName, "--", "docker", "volume", "rm", name])
    }

    func colimaVersion() async throws -> String {
        let output = try await runOnce(["version"])
        let first = output.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return first
            .replacingOccurrences(of: "colima version ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    func startContainer(profileName: String, containerID: String) async throws -> String {
        try await runOnce(["ssh", "-p", profileName, "--", "docker", "start", containerID])
    }

    func stopContainer(profileName: String, containerID: String) async throws -> String {
        try await runOnce(["ssh", "-p", profileName, "--", "docker", "stop", containerID])
    }

    func restartContainer(profileName: String, containerID: String) async throws -> String {
        try await runOnce(["ssh", "-p", profileName, "--", "docker", "restart", containerID])
    }

    func containerLogs(profileName: String, containerID: String, tail: Int = 500) -> AsyncThrowingStream<String, Error> {
        stream(["ssh", "-p", profileName, "--", "docker", "logs", "-f", "--tail", "\(tail)", containerID])
    }

    func imageLayers(profileName: String, imageID: String) async throws -> [DockerImageLayer] {
        // `docker history` is the primary source — always works and gives us
        // per-layer command + size + created age. BuildKit sometimes strips
        // History from `docker image inspect`, so we can't rely on that for
        // the primary data. We do still call inspect once to enrich with
        // sha256 digests from RootFS.Layers[].
        let historyText = try await runOnce([
            "ssh", "-p", profileName, "--",
            "docker", "history", "--no-trunc", "--format", "{{json .}}", imageID
        ])
        let inspectText = try await runOnce([
            "ssh", "-p", profileName, "--",
            "docker", "image", "inspect", "--format", "{{json .}}", imageID
        ])

        // docker history prints newest-first; reverse to oldest-first (base
        // at index 0), matching how dive presents the stack.
        let historyLines = historyText.split(separator: "\n", omittingEmptySubsequences: true)
        let rawEntries: [RawHistoryLine] = historyLines.compactMap { line in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RawHistoryLine.self, from: data)
        }
        let orderedEntries = Array(rawEntries.reversed())

        // Pull digests from RootFS.Layers[] if inspect is parseable. Not
        // fatal if it isn't — we just skip digest enrichment.
        var digests: [String] = []
        if let data = inspectText.data(using: .utf8),
           let root = try? JSONDecoder().decode(RawInspectRootFSOnly.self, from: data) {
            digests = root.rootFS.layers ?? []
        }

        var digestCursor = 0
        var out: [DockerImageLayer] = []
        for entry in orderedEntries {
            // Docker history doesn't return an explicit "empty layer" flag on
            // the CLI — infer from size == "0B" (WORKDIR / ENV / LABEL etc).
            let isEmpty = entry.size.trimmingCharacters(in: .whitespaces) == "0B"
            var digest: String? = nil
            if !isEmpty, digestCursor < digests.count {
                digest = digests[digestCursor]
                digestCursor += 1
            }
            out.append(DockerImageLayer(
                createdAt: entry.createdAt,
                createdBy: entry.createdBy,
                comment: entry.comment,
                isEmptyLayer: isEmpty,
                digest: digest,
                size: entry.size
            ))
        }
        return out
    }

    func inspectContainer(profileName: String, containerID: String) async throws -> String {
        let raw = try await runOnce(["ssh", "-p", profileName, "--", "docker", "inspect", containerID])
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: pretty, encoding: .utf8)
        else { return raw }
        return text
    }

    // Path to the colima binary — used by callers that need to shell out
    // themselves (e.g. AppleScript that opens Terminal.app with `colima ssh`).
    var binary: String { binaryPath }

    func delete(profileName: String) -> AsyncThrowingStream<String, Error> {
        stream(["delete", profileName, "--force"])
    }

    func stop(profileName: String) -> AsyncThrowingStream<String, Error> {
        stream(["stop", profileName])
    }

    func restart(profileName: String) -> AsyncThrowingStream<String, Error> {
        stream(["restart", profileName])
    }

    // MARK: - Private

    // Homebrew paths so spawned `colima` can find `limactl`, `docker`, etc.
    // Apps launched by LaunchServices otherwise inherit only /usr/bin:/bin:...
    private static func spawnEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let existingParts = existing.split(separator: ":").map(String.init)
        let merged = (brewPaths + existingParts.filter { !brewPaths.contains($0) }).joined(separator: ":")
        env["PATH"] = merged
        return env
    }

    private func runOnce(_ arguments: [String], timeout: TimeInterval = 15) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw ColimaError.binaryNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        process.environment = Self.spawnEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Watchdog: SIGTERM the process if it hasn't exited within `timeout`.
        // Prevents the caller's continuation from wedging forever if the ssh
        // hangs (VM booting, ssh not yet listening, etc).
        let didTimeout = TimeoutFlag()
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(timeout))
            if process.isRunning {
                didTimeout.value = true
                process.terminate()
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                watchdog.cancel()
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""

                if didTimeout.value {
                    continuation.resume(throwing: ColimaError.commandFailed(
                        exitCode: -1,
                        message: "Timed out after \(Int(timeout))s — \(arguments.joined(separator: " "))"
                    ))
                    return
                }
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else {
                    continuation.resume(throwing: ColimaError.commandFailed(
                        exitCode: proc.terminationStatus,
                        message: (stderr.isEmpty ? stdout : stderr)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                watchdog.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private func stream(_ arguments: [String]) -> AsyncThrowingStream<String, Error> {
        let binary = binaryPath
        return AsyncThrowingStream { continuation in
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                continuation.finish(throwing: ColimaError.binaryNotFound)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            process.environment = Self.spawnEnvironment()

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutBuffer = LineBuffer()
            let stderrBuffer = LineBuffer()
            let stderrCapture = StderrCapture()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                for line in stdoutBuffer.push(chunk) {
                    continuation.yield(line)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                stderrCapture.tail.append(chunk)
                for line in stderrBuffer.push(chunk) {
                    continuation.yield(line)
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                for line in stdoutBuffer.flush() { continuation.yield(line) }
                for line in stderrBuffer.flush() { continuation.yield(line) }

                if proc.terminationStatus == 0 {
                    continuation.finish()
                } else {
                    let tail = stderrCapture.tail
                        .split(separator: "\n")
                        .suffix(3)
                        .joined(separator: " · ")
                    continuation.finish(throwing: ColimaError.commandFailed(
                        exitCode: proc.terminationStatus,
                        message: tail.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

// Buffers a single stream's output, emitting one string per newline.
// Handles \r-based spinner redraws by keeping only the final frame within a line.
private final class LineBuffer {
    private var pending = ""

    func push(_ chunk: String) -> [String] {
        pending += chunk
        var out: [String] = []
        while let nl = pending.range(of: "\n") {
            let raw = String(pending[..<nl.lowerBound])
            pending.removeSubrange(..<nl.upperBound)
            let cleaned: String
            if let lastCR = raw.range(of: "\r", options: .backwards) {
                cleaned = String(raw[lastCR.upperBound...])
            } else {
                cleaned = raw
            }
            let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                out.append(trimmed)
            }
        }
        return out
    }

    func flush() -> [String] {
        defer { pending = "" }
        let trimmed = pending.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? [] : [trimmed]
    }
}

private final class StderrCapture {
    var tail: String = ""
}

// Boxed boolean so the watchdog Task and the process's terminationHandler
// (which runs on a background queue) can share the "did we time out?" state.
private final class TimeoutFlag: @unchecked Sendable {
    var value: Bool = false
}

private struct RawInspectRootFSOnly: Decodable {
    let rootFS: RootFS

    private enum CodingKeys: String, CodingKey {
        case rootFS = "RootFS"
    }

    struct RootFS: Decodable {
        let layers: [String]?
        private enum CodingKeys: String, CodingKey {
            case layers = "Layers"
        }
    }
}

private struct RawHistoryLine: Decodable {
    let id: String
    let createdAt: String
    let createdBy: String
    let size: String
    let comment: String

    private enum CodingKeys: String, CodingKey {
        case id         = "ID"
        case createdAt  = "CreatedAt"
        case createdBy  = "CreatedBy"
        case size       = "Size"
        case comment    = "Comment"
    }
}

private struct RawImage: Decodable {
    let id: String
    let repository: String
    let tag: String
    let size: String
    let createdSince: String

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case size = "Size"
        case createdSince = "CreatedSince"
    }
}

private struct RawContainer: Decodable {
    let id: String
    let names: String
    let image: String
    let state: String
    let status: String
    let size: String
    let ports: String

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case size = "Size"
        case ports = "Ports"
    }
}

private struct RawVolume: Decodable {
    let name: String
    let driver: String
    let mountpoint: String
    let links: String

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
        case mountpoint = "Mountpoint"
        case links = "Links"
    }
}

private struct RawProfile: Decodable {
    let name: String
    let status: String
    let arch: String?
    let cpus: Int?
    let memory: Int64?
    let disk: Int64?
    let address: String?
    let runtime: String?

    func toProfile() -> Profile {
        let statusEnum: Profile.Status
        switch status.lowercased() {
        case "running": statusEnum = .running
        case "stopped": statusEnum = .stopped
        case "starting": statusEnum = .starting
        case "stopping": statusEnum = .stopping
        default: statusEnum = .unknown
        }
        let socketPath = ("~/.colima/\(name)/docker.sock" as NSString).expandingTildeInPath
        return Profile(
            name: name,
            status: statusEnum,
            cpu: cpus ?? 0,
            memoryGB: Int((memory ?? 0) / 1_073_741_824),
            diskGB: Int((disk ?? 0) / 1_073_741_824),
            runtime: runtime ?? "docker",
            arch: arch ?? "",
            address: address ?? "",
            dockerSocket: URL(fileURLWithPath: socketPath)
        )
    }
}
