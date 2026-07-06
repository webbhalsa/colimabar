import Foundation

struct DockerInfo: Equatable {
    let serverVersion: String
    let storageDriver: String
    let cgroupDriver: String
    let kernelVersion: String
    let operatingSystem: String
    let architecture: String
    let dockerRootDir: String
    let loggingDriver: String
    let cpuCount: Int
    let totalMemory: Int64
    let insecureRegistries: [String]
    let registryMirrors: [String]

    static func parse(_ raw: String) -> DockerInfo? {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONDecoder().decode(RawInfo.self, from: data)
        else { return nil }
        return DockerInfo(
            serverVersion: object.serverVersion,
            storageDriver: object.driver,
            cgroupDriver: object.cgroupDriver ?? "",
            kernelVersion: object.kernelVersion,
            operatingSystem: object.operatingSystem,
            architecture: object.architecture,
            dockerRootDir: object.dockerRootDir,
            loggingDriver: object.loggingDriver,
            cpuCount: object.ncpu,
            totalMemory: object.memTotal,
            insecureRegistries: object.registryConfig?.insecureRegistryCIDRs ?? [],
            registryMirrors: object.registryConfig?.mirrors ?? []
        )
    }
}

private struct RawInfo: Decodable {
    let serverVersion: String
    let driver: String
    let cgroupDriver: String?
    let kernelVersion: String
    let operatingSystem: String
    let architecture: String
    let dockerRootDir: String
    let loggingDriver: String
    let ncpu: Int
    let memTotal: Int64
    let registryConfig: RawRegistryConfig?

    private enum CodingKeys: String, CodingKey {
        case serverVersion   = "ServerVersion"
        case driver          = "Driver"
        case cgroupDriver    = "CgroupDriver"
        case kernelVersion   = "KernelVersion"
        case operatingSystem = "OperatingSystem"
        case architecture    = "Architecture"
        case dockerRootDir   = "DockerRootDir"
        case loggingDriver   = "LoggingDriver"
        case ncpu            = "NCPU"
        case memTotal        = "MemTotal"
        case registryConfig  = "RegistryConfig"
    }
}

private struct RawRegistryConfig: Decodable {
    let insecureRegistryCIDRs: [String]?
    let mirrors: [String]?

    private enum CodingKeys: String, CodingKey {
        case insecureRegistryCIDRs = "InsecureRegistryCIDRs"
        case mirrors               = "Mirrors"
    }
}
