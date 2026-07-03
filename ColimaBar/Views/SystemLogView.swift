import SwiftUI
import AppKit

struct SystemLogView: View {
    @ObservedObject private var log = AppLog.shared

    @State private var minLevel: LogLevel = .info
    @State private var search: String = ""
    @State private var autoScroll: Bool = true

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 420, idealHeight: 520)
    }

    private var filtered: [LogEntry] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return log.entries.filter { entry in
            guard entry.level >= minLevel else { return false }
            if needle.isEmpty { return true }
            return entry.category.lowercased().contains(needle)
                || entry.message.lowercased().contains(needle)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("Level", selection: $minLevel) {
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            TextField("Filter", text: $search, prompt: Text("Search…"))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            Text("\(filtered.count) / \(log.entries.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { entry in
                        row(entry)
                            .id(entry.id)
                    }
                }
                .padding(10)
            }
            .background(Color.gray.opacity(0.06))
            .onChange(of: log.entries.count) { _, _ in
                guard autoScroll, let last = filtered.last else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(entry.level.label)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(color(for: entry.level))
                .frame(width: 48, alignment: .leading)
            Text(entry.category)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.blue)
                .frame(width: 90, alignment: .leading)
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug:   return .secondary
        case .info:    return .primary
        case .warning: return .orange
        case .error:   return .red
        }
    }

    private var footer: some View {
        HStack {
            Text(log.logFileURL.path)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([log.logFileURL])
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(log.logFileURL.path, forType: .string)
            }
            Button("Clear") {
                log.clear()
            }
            .disabled(log.entries.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
