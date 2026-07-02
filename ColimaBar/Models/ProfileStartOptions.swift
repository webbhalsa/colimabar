import Foundation

struct ProfileStartOptions: Equatable {
    var cpu: Int
    var memoryGB: Int
    var diskGB: Int
    var runtime: String

    static let runtimes = ["docker", "containerd", "incus"]

    init(cpu: Int, memoryGB: Int, diskGB: Int, runtime: String) {
        self.cpu = cpu
        self.memoryGB = memoryGB
        self.diskGB = diskGB
        self.runtime = runtime
    }

    init(from profile: Profile) {
        self.init(
            cpu: max(profile.cpu, 1),
            memoryGB: max(profile.memoryGB, 1),
            diskGB: max(profile.diskGB, 20),
            runtime: ProfileStartOptions.runtimes.contains(profile.runtime) ? profile.runtime : "docker"
        )
    }

    var colimaArgs: [String] {
        [
            "--cpu", "\(cpu)",
            "--memory", "\(memoryGB)",
            "--disk", "\(diskGB)",
            "--runtime", runtime,
        ]
    }
}
