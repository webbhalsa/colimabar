import Foundation
import os

enum LogLevel: String, CaseIterable, Comparable, Codable {
    case debug, info, warning, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .debug:   return 0
        case .info:    return 1
        case .warning: return 2
        case .error:   return 3
        }
    }

    var label: String {
        switch self {
        case .debug:   return "DEBUG"
        case .info:    return "INFO"
        case .warning: return "WARN"
        case .error:   return "ERROR"
        }
    }
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
}

@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    @Published private(set) var entries: [LogEntry] = []
    private let memoryCapacity = 2000
    private let osLogger = Logger(subsystem: "se.kry.ColimaBar", category: "app")

    // Rolling on-disk log: `~/Library/Logs/ColimaBar/colimabar.log`
    // Pruned on startup when it grows past `fileTruncateAbove` bytes
    // — we keep the trailing `fileKeepBytes` from the previous file.
    private let fileURL: URL
    private let fileTruncateAbove: UInt64 = 2_000_000  // 2 MB
    private let fileKeepBytes: UInt64 = 500_000  // 0.5 MB
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let logsDir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ColimaBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.fileURL = logsDir.appendingPathComponent("colimabar.log")
        pruneOnStartup()
    }

    var logFileURL: URL { fileURL }

    func log(_ level: LogLevel, _ category: String, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
        entries.append(entry)
        if entries.count > memoryCapacity {
            entries.removeFirst(entries.count - memoryCapacity)
        }
        emitToOSLog(level: level, combined: "[\(category)] \(message)")
        appendToFile(entry)
    }

    func clear() {
        entries.removeAll()
    }

    nonisolated static func log(_ level: LogLevel, _ category: String, _ message: String) {
        Task { @MainActor in
            AppLog.shared.log(level, category, message)
        }
    }

    // MARK: - Private

    private func emitToOSLog(level: LogLevel, combined: String) {
        switch level {
        case .debug:   osLogger.debug("\(combined, privacy: .public)")
        case .info:    osLogger.info("\(combined, privacy: .public)")
        case .warning: osLogger.warning("\(combined, privacy: .public)")
        case .error:   osLogger.error("\(combined, privacy: .public)")
        }
    }

    private func appendToFile(_ entry: LogEntry) {
        let line = "\(Self.isoFormatter.string(from: entry.timestamp)) \(entry.level.label.padding(toLength: 5, withPad: " ", startingAt: 0)) [\(entry.category)] \(entry.message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func pruneOnStartup() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            guard size > fileTruncateAbove else { return }
            let startOffset = size - fileKeepBytes
            try handle.seek(toOffset: startOffset)
            let tail = try handle.readToEnd() ?? Data()
            // Drop the partial first line so the file starts cleanly
            let clean: Data
            if let newlineIdx = tail.firstIndex(of: 0x0A) {
                clean = tail.subdata(in: (newlineIdx + 1)..<tail.count)
            } else {
                clean = tail
            }
            let header = "--- log truncated at startup, kept trailing \(clean.count) bytes ---\n"
            var out = Data()
            if let hData = header.data(using: .utf8) { out.append(hData) }
            out.append(clean)
            try out.write(to: fileURL, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
