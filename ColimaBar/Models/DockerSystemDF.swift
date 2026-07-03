import Foundation

struct DockerSystemDF: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String { type }
        let type: String
        let totalCount: Int
        let activeCount: Int
        let sizeBytes: Int64
        let reclaimableBytes: Int64
    }

    let rows: [Row]
    let sampledAt: Date

    var totalReclaimableBytes: Int64 { rows.reduce(0) { $0 + $1.reclaimableBytes } }

    // Only sum what `docker system prune -f` will reliably recover:
    // stopped containers and build cache are removed in full, while the
    // Images "Reclaimable" count from `docker system df` includes tagged
    // unused images that safe prune won't touch — so we deliberately omit
    // it and Local Volumes here. This underestimates when dangling images
    // are present, but never overstates.
    var safelyReclaimableBytes: Int64 {
        rows
            .filter { $0.type == "Containers" || $0.type == "Build Cache" }
            .reduce(0) { $0 + $1.reclaimableBytes }
    }

    static func parse(_ output: String, sampledAt: Date) -> DockerSystemDF? {
        var rows: [Row] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let raw = try? JSONDecoder().decode(RawRow.self, from: data)
            else { continue }
            rows.append(Row(
                type: raw.type,
                totalCount: Int(raw.totalCount) ?? 0,
                activeCount: Int(raw.active) ?? 0,
                sizeBytes: parseSize(raw.size),
                reclaimableBytes: parseSize(raw.reclaimable)
            ))
        }
        return rows.isEmpty ? nil : DockerSystemDF(rows: rows, sampledAt: sampledAt)
    }

    private static func parseSize(_ s: String) -> Int64 {
        guard let match = s.firstMatch(of: /([\d.]+)\s*([KMGT]?B)/) else { return 0 }
        let value = Double(match.output.1) ?? 0
        let multiplier: Double
        switch String(match.output.2).uppercased() {
        case "B":  multiplier = 1
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default:   multiplier = 1
        }
        return Int64(value * multiplier)
    }
}

private struct RawRow: Decodable {
    let type: String
    let totalCount: String
    let active: String
    let size: String
    let reclaimable: String

    private enum CodingKeys: String, CodingKey {
        case type = "Type"
        case totalCount = "TotalCount"
        case active = "Active"
        case size = "Size"
        case reclaimable = "Reclaimable"
    }
}
