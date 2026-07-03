import SwiftUI

struct ContainerLogsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let target = appState.containerLogTarget {
                LogsStreamView(target: target)
                    .id(target.id)
            } else {
                idle
            }
        }
        .frame(minWidth: 640, idealWidth: 780, minHeight: 380, idealHeight: 460)
    }

    private var idle: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.alignleft")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("No container selected")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct LogsStreamView: View {
    let target: AppState.ContainerLogTarget
    @EnvironmentObject var appState: AppState

    @State private var lines: [String] = []
    @State private var status: Status = .streaming
    @State private var autoScroll: Bool = true

    private enum Status: Equatable {
        case streaming
        case ended
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logsView
            Divider()
            footer
        }
        .task(id: target.id) {
            await stream()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            statusIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(target.containerName)
                    .font(.headline)
                Text("\(target.profileName) · \(String(target.containerID.prefix(12)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(12)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .streaming:
            ProgressView().controlSize(.small)
        case .ended:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private var logsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .id(idx)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .background(Color.gray.opacity(0.06))
            .onChange(of: lines.count) { _, count in
                guard autoScroll, count > 0 else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            switch status {
            case .streaming:
                Text("Following \(lines.count) lines…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .ended:
                Text("Stream ended · \(lines.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Clear") { lines.removeAll() }
                .disabled(lines.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stream() async {
        lines.removeAll()
        status = .streaming
        let stream = ColimaService().containerLogs(profileName: target.profileName, containerID: target.containerID)
        do {
            for try await line in stream {
                lines.append(line)
            }
            status = .ended
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
