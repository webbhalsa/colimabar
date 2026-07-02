import SwiftUI

struct ProgressHUDView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if let op = appState.runningOperation {
                OperationCard(operation: op)
            } else {
                IdleCard()
            }
        }
        .padding(16)
        .frame(minWidth: 440, idealWidth: 480, maxWidth: 640)
    }
}

private struct OperationCard: View {
    @ObservedObject var operation: RunningOperation
    @State private var showLog = false
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            latestLineBox
            DisclosureGroup(isExpanded: $showLog) {
                logView
            } label: {
                Text("Log · \(operation.lines.count) line\(operation.lines.count == 1 ? "" : "s")")
                    .font(.caption)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(operation.action) \(operation.profileName)")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !operation.isRunning {
                Button("Close") { dismissWindow() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch operation.state {
        case .running:
            ProgressView().controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .imageScale(.large)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .imageScale(.large)
        }
    }

    private var subtitle: String {
        switch operation.state {
        case .running:
            return "Running · \(elapsed)"
        case .succeeded:
            return "Completed in \(elapsed)"
        case .failed(let msg):
            return msg
        }
    }

    private var elapsed: String {
        let secs = Int(Date().timeIntervalSince(operation.startedAt))
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }

    private var latestLineBox: some View {
        Text(operation.latestLine)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(operation.lines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .id(idx)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(height: 220)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: operation.lines.count) { _, count in
                guard count > 0 else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .onAppear {
                guard operation.lines.count > 0 else { return }
                proxy.scrollTo(operation.lines.count - 1, anchor: .bottom)
            }
        }
    }
}

private struct IdleCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz")
                .foregroundStyle(.secondary)
                .imageScale(.large)
            Text("No colima operation running")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
