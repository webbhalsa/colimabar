import SwiftUI
import AppKit

struct ImageLayersView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let target = appState.imageLayersTarget {
                LayersBrowser(target: target).id(target.id)
            } else {
                idle
            }
        }
        .frame(minWidth: 820, idealWidth: 980, minHeight: 500, idealHeight: 620)
    }

    private var idle: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("No image selected").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LayersBrowser: View {
    let target: AppState.ImageLayersTarget

    @State private var layers: [DockerImageLayer] = []
    @State private var selected: Int = 0
    @State private var loading: Bool = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading image history…").foregroundStyle(.secondary).font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                Text(error).foregroundStyle(.red).font(.caption)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                HSplitView {
                    layersList
                        .frame(minWidth: 220, idealWidth: 300, maxWidth: 400)
                    layerDetails
                        .frame(minWidth: 380)
                }
                Divider()
                imageDetails
            }
        }
        .task(id: target.id) { await load() }
    }

    // MARK: Left pane — compact layer list

    private var layersList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Layers").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(layers.count)").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
            List(selection: $selected) {
                ForEach(Array(layers.enumerated()), id: \.offset) { idx, layer in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(layer.size)
                            .font(.system(.caption, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(layer.isEmptyLayer ? .secondary : .primary)
                            .frame(width: 62, alignment: .trailing)
                        Text(displayCommand(for: layer, at: idx))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(layer.isEmptyLayer ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 1)
                    .tag(idx)
                }
            }
            .listStyle(.plain)
            Divider()
            HStack {
                Image(systemName: "info.circle")
                    .imageScale(.small)
                Text("Sizes are uncompressed (docker history).")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
    }

    // MARK: Right pane — layer details

    @ViewBuilder
    private var layerDetails: some View {
        if selected < layers.count {
            let layer = layers[selected]
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Layer #\(selected)").font(.headline)
                        if layer.isEmptyLayer {
                            Text("no filesystem change")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .clipShape(Capsule())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(layer.size)
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    Divider()

                    fieldSection("Command") {
                        Text(displayCommand(for: layer, at: selected))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if let digest = layer.digest {
                        field("Digest", digest, monospaced: true)
                    } else {
                        field("Digest", "— (empty layer)")
                    }
                    field("Created", shortDate(layer.createdAt))
                    if !layer.comment.isEmpty {
                        field("Comment", layer.comment)
                    }
                }
                .padding(14)
            }
        } else {
            Text("Select a layer").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func shortDate(_ raw: String) -> String {
        // History timestamps are ISO 8601 like "2025-11-10T12:34:56Z". Keep
        // the date and drop the milliseconds/timezone noise for display.
        if let iso = raw.range(of: "T") {
            let date = raw[..<iso.lowerBound]
            let time = raw[iso.upperBound...].prefix(8)
            return "\(date) \(time)"
        }
        return raw
    }

    // MARK: Bottom — image details

    private var imageDetails: some View {
        HStack(alignment: .top, spacing: 24) {
            fieldColumn("Image", target.imageDisplayName)
            fieldColumn("Total size", target.imageSize)
            fieldColumn("Layers", "\(layers.count)")
            fieldColumn("Image ID", String(target.imageID.replacingOccurrences(of: "sha256:", with: "").prefix(12)), monospaced: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.gray.opacity(0.05))
    }

    // MARK: helpers

    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            content()
        }
    }

    private func field(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
        }
    }

    private func fieldColumn(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .textSelection(.enabled)
        }
    }

    // Layer #0 is always the base image (produced by a `FROM` in the child
    // Dockerfile), but its `CreatedBy` on the wire is the base's own build
    // command. Prefix with "FROM base: " so it reads like dive's "FROM blobs".
    private func displayCommand(for layer: DockerImageLayer, at index: Int) -> String {
        let base = compactCommand(layer.createdBy)
        return index == 0 ? "FROM base: \(base)" : base
    }

    private func compactCommand(_ raw: String) -> String {
        var s = raw
        for prefix in [
            "/bin/sh -c #(nop) ",
            "/bin/sh -c ",
            "|1 ",
            "|2 ",
            "|3 ",
        ] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func load() async {
        loading = true
        error = nil
        do {
            layers = try await ColimaService().imageLayers(
                profileName: target.profileName,
                imageID: target.imageID
            )
            selected = 0
            AppLog.log(.debug, "image-layers",
                       "loaded \(layers.count) layers for \(target.imageID.prefix(12))")
        } catch {
            self.error = error.localizedDescription
            AppLog.log(.error, "image-layers",
                       "load failed for \(target.imageID.prefix(12)): \(error.localizedDescription)")
        }
        loading = false
    }
}
