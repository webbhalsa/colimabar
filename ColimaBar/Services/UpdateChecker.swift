import Foundation

enum UpdateChecker {
    private static let feedURL = URL(string: "https://api.github.com/repos/webbhalsa/colimabar/releases/latest")!
    private static let colimaFeedURL = URL(string: "https://api.github.com/repos/abiosoft/colima/releases/latest")!

    static func fetchLatest() async -> UpdateInfo? {
        let current = currentVersion()
        guard shouldCheck(currentVersion: current) else { return nil }
        return await fetchFrom(feedURL, current: current)
    }

    static func fetchLatestColima(current: String) async -> UpdateInfo? {
        guard !current.isEmpty else { return nil }
        return await fetchFrom(colimaFeedURL, current: current)
    }

    private static func fetchFrom(_ url: URL, current: String) async -> UpdateInfo? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let payload = try? JSONDecoder().decode(RawRelease.self, from: data)
        else { return nil }

        let latest = payload.tagName.hasPrefix("v")
            ? String(payload.tagName.dropFirst())
            : payload.tagName

        guard UpdateInfo.isNewer(latest: latest, than: current) else { return nil }

        return UpdateInfo(
            currentVersion: current,
            latestVersion: latest,
            releaseURL: URL(string: payload.htmlURL) ?? url,
            publishedAt: payload.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
        )
    }

    private static func currentVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }

    private static func shouldCheck(currentVersion: String) -> Bool {
        !currentVersion.isEmpty
            && currentVersion.lowercased() != "dev"
            && !currentVersion.hasPrefix("0.0")
    }
}

private struct RawRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let publishedAt: String?

    private enum CodingKeys: String, CodingKey {
        case tagName     = "tag_name"
        case htmlURL     = "html_url"
        case publishedAt = "published_at"
    }
}
