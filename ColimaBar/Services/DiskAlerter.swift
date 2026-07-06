import Foundation
import UserNotifications

@MainActor
final class DiskAlerter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = DiskAlerter()

    private let alertThreshold: Double = 0.90
    private let throttleInterval: TimeInterval = 6 * 3600  // 6 hours
    private let defaultsKey = "diskAlertAt"
    private var authorized: Bool = false

    private override init() {
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                AppLog.log(.warning, "notifications", "auth request failed: \(error.localizedDescription)")
            } else {
                AppLog.log(.info, "notifications", "notifications authorized=\(granted)")
            }
        }
    }

    func evaluate(_ usage: DiskUsage, profileName: String) {
        guard usage.usedFraction >= alertThreshold else { return }
        let key = "\(defaultsKey)/\(profileName)"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > throttleInterval else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        let percent = Int(usage.usedFraction * 100)
        let free = ByteCountFormatter.string(fromByteCount: usage.availableBytes, countStyle: .decimal)

        let content = UNMutableNotificationContent()
        content.title = "\(profileName): docker disk almost full"
        content.body = "\(percent)% used, \(free) free. Open ColimaBar and Reclaim or Deep prune to recover space."
        content.sound = .default

        let request = UNNotificationRequest(identifier: "disk-full-\(profileName)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLog.log(.error, "notifications", "post failed: \(error.localizedDescription)")
            } else {
                AppLog.log(.info, "notifications", "posted disk-full notification for \(profileName) (\(percent)%)")
            }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
