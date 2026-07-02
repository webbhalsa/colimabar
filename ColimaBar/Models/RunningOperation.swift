import Foundation

final class RunningOperation: ObservableObject, Identifiable {
    let id = UUID()
    let profileName: String
    let action: String
    let startedAt = Date()

    @Published var lines: [String] = []
    @Published var state: State = .running

    enum State: Equatable {
        case running
        case succeeded
        case failed(String)
    }

    init(profileName: String, action: String) {
        self.profileName = profileName
        self.action = action
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var latestLine: String {
        lines.reversed().first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            ?? "Starting…"
    }
}
