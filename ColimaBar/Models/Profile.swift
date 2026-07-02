import Foundation

struct Profile: Identifiable, Equatable {
    var id: String { name }
    let name: String
    var status: Status
    var cpu: Int
    var memoryGB: Int
    var diskGB: Int
    var runtime: String
    var arch: String
    var address: String
    var dockerSocket: URL?

    enum Status: String {
        case running = "Running"
        case stopped = "Stopped"
        case starting = "Starting"
        case stopping = "Stopping"
        case unknown = "Unknown"
    }
}
