import Foundation

struct DockerImageLayer: Identifiable, Equatable {
    let id: UUID = UUID()
    let createdAt: String
    let createdBy: String
    let comment: String
    let isEmptyLayer: Bool
    // sha256 digest of the layer's filesystem tarball. nil for empty history
    // entries (WORKDIR / ENV / LABEL / etc — instructions that don't produce
    // a filesystem change and therefore have no layer digest).
    let digest: String?
    // Human-readable size string as reported by `docker history` (e.g.
    // "72.8MB", "0B"). Docker doesn't cleanly expose per-layer bytes on the
    // CLI, so we carry the display string directly rather than parse+reformat.
    let size: String
}
