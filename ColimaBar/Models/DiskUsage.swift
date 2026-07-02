import Foundation

struct DiskUsage: Equatable {
    let totalBytes: Int64
    let usedBytes: Int64
    let availableBytes: Int64
    let sampledAt: Date

    var usedFraction: Double {
        totalBytes > 0 ? min(1.0, Double(usedBytes) / Double(totalBytes)) : 0
    }

    static func parse(dfOutput: String, sampledAt: Date) -> DiskUsage? {
        let lines = dfOutput.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 2 else { return nil }
        let fields = lines[1].split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 4,
              let totalKB = Int64(fields[1]),
              let usedKB = Int64(fields[2]),
              let availKB = Int64(fields[3])
        else { return nil }
        return DiskUsage(
            totalBytes: totalKB * 1024,
            usedBytes: usedKB * 1024,
            availableBytes: availKB * 1024,
            sampledAt: sampledAt
        )
    }
}
