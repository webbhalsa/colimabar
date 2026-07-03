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
    let ports: [PortMapping]

    struct PortMapping: Identifiable, Equatable, Hashable {
        var id: String { "\(hostIP):\(hostPort)->\(containerPort)/\(proto)" }
        let hostIP: String
        let hostPort: Int
        let containerPort: Int
        let proto: String

        var isPublished: Bool { hostPort > 0 }

        var hostIPForURL: String {
            if hostIP.isEmpty || hostIP == "0.0.0.0" || hostIP == "::" { return "localhost" }
            return hostIP
        }

        var httpURL: URL? {
            guard isPublished else { return nil }
            let scheme = containerPort == 443 || containerPort == 8443 ? "https" : "http"
            return URL(string: "\(scheme)://\(hostIPForURL):\(hostPort)")
        }

        var isLikelyHTTP: Bool {
            let httpPorts: Set<Int> = [80, 443, 3000, 4000, 4200, 5000, 5173, 8000, 8080, 8443, 8888, 9000, 9090]
            return httpPorts.contains(containerPort) || httpPorts.contains(hostPort)
        }

        static func parseList(_ raw: String) -> [PortMapping] {
            raw.split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap(parse)
        }

        static func parse(_ s: String) -> PortMapping? {
            if let arrow = s.range(of: "->") {
                let hostPart = s[..<arrow.lowerBound]
                let containerPart = s[arrow.upperBound...]
                guard let colon = hostPart.range(of: ":", options: .backwards),
                      let hostPort = Int(hostPart[colon.upperBound...])
                else { return nil }
                var hostIP = String(hostPart[..<colon.lowerBound])
                if hostIP.hasPrefix("[") && hostIP.hasSuffix("]") {
                    hostIP = String(hostIP.dropFirst().dropLast())
                }
                guard let slash = containerPart.range(of: "/"),
                      let containerPort = Int(containerPart[..<slash.lowerBound])
                else { return nil }
                let proto = String(containerPart[slash.upperBound...])
                return PortMapping(hostIP: hostIP, hostPort: hostPort, containerPort: containerPort, proto: proto)
            } else {
                guard let slash = s.range(of: "/"),
                      let containerPort = Int(s[..<slash.lowerBound])
                else { return nil }
                let proto = String(s[slash.upperBound...])
                return PortMapping(hostIP: "", hostPort: 0, containerPort: containerPort, proto: proto)
            }
        }
    }
}

struct DockerVolume: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let driver: String
    let mountpoint: String
    let links: String
}

struct ContainerStats: Equatable {
    let containerID: String
    let name: String
    let cpuPercent: String
    let memPercent: String
    let memUsage: String
    let netIO: String
    let blockIO: String

    static func parse(_ line: String) -> ContainerStats? {
        guard let data = line.data(using: .utf8),
              let raw = try? JSONDecoder().decode(RawStats.self, from: data)
        else { return nil }
        return ContainerStats(
            containerID: raw.id,
            name: raw.name,
            cpuPercent: raw.cpuPerc,
            memPercent: raw.memPerc,
            memUsage: raw.memUsage,
            netIO: raw.netIO,
            blockIO: raw.blockIO
        )
    }
}

private struct RawStats: Decodable {
    let id: String
    let name: String
    let cpuPerc: String
    let memPerc: String
    let memUsage: String
    let netIO: String
    let blockIO: String

    private enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case cpuPerc = "CPUPerc"
        case memPerc = "MemPerc"
        case memUsage = "MemUsage"
        case netIO = "NetIO"
        case blockIO = "BlockIO"
    }
}
