import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @State private var launchAtLogin: Bool = false
    @State private var status: SMAppService.Status = .notRegistered
    @State private var lastError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start ColimaBar at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        applyLaunchAtLogin(newValue)
                    }
                statusLine
                if let err = lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("About") {
                LabeledContent("Version", value: bundleString("CFBundleShortVersionString") ?? "?")
                LabeledContent("Build",   value: bundleString("CFBundleVersion") ?? "?")
                LabeledContent("Location") {
                    Text(Bundle.main.bundlePath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .task { refreshStatus() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .enabled:
            Label("Enabled — ColimaBar will launch when you log in.",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .requiresApproval:
            Label("Requires approval — open System Settings › General › Login Items and enable ColimaBar.",
                  systemImage: "hand.raised.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        case .notRegistered:
            Text("Not enabled.")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .notFound:
            Label("Login item not found. Toggling on will register it.",
                  systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        @unknown default:
            Text("Unknown status.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func refreshStatus() {
        status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refreshStatus()
    }

    private func bundleString(_ key: String) -> String? {
        Bundle.main.infoDictionary?[key] as? String
    }
}
