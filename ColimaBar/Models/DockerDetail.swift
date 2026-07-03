import Foundation

struct DockerImage: Identifiable, Equatable {
    var id: String { imageID }
    let imageID: String
    let repository: String
    let tag: String
    let size: String
    let createdSince: String

    var displayName: String {
        if repository == "<none>" && tag == "<none>" { return "<dangling>" }
        return "\(repository):\(tag)"
    }
}

struct DockerContainer: Identifiable, Equatable {
    var id: String { containerID }
    let containerID: String
    let name: String
    let image: String
    let state: String
    let status: String
    let size: String
}

struct DockerVolume: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let driver: String
    let mountpoint: String
    let links: String
}
