import SwiftUI
import AppKit

struct ContainerInspectView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let target = appState.containerInspectTarget {
                InspectStreamView(target: target).id(target.id)
            } else {
                idle
            }
        }
        .frame(minWidth: 640, idealWidth: 780, minHeight: 420, idealHeight: 520)
    }

    private var idle: some View {
        VStack(spacing: 12) {
            Image(systemName: "info.circle")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("No container selected").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectStreamView: View {
    let target: AppState.ContainerInspectTarget

    @State private var json: String = ""
    @State private var loading: Bool = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: target.id) { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(target.containerName).font(.headline)
                Text("\(target.profileName) · \(String(target.containerID.prefix(12)))")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button("Copy JSON") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(json, forType: .string)
            }
            .disabled(json.isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Inspecting…").foregroundStyle(.secondary).font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            Text(error).foregroundStyle(.red).font(.caption)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.gray.opacity(0.06))
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            json = try await ColimaService().inspectContainer(
                profileName: target.profileName,
                containerID: target.containerID
            )
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
