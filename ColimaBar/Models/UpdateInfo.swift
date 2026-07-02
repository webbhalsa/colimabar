import Foundation

struct UpdateInfo: Equatable {
    let currentVersion: String
    let latestVersion: String
    let releaseURL: URL
    let publishedAt: Date?

    static func isNewer(latest: String, than current: String) -> Bool {
        let l = parts(from: latest)
        let c = parts(from: current)
        for i in 0..<max(l.count, c.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < c.count ? c[i] : 0
            if a > b { return true }
            if a < b { return false }
        }
        return false
    }

    private static func parts(from version: String) -> [Int] {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        return core.split(separator: ".").compactMap { Int($0) }
    }
}
