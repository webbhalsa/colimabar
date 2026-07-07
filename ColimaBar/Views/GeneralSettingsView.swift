import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin: Bool = false
    @State private var status: SMAppService.Status = .notRegistered
    @State private var lastError: String?

    var body: some View {
        Form {
            if let update = appState.updateAvailable {
                Section {
                    updateNotice(update)
                }
            }

            if appState.profiles.isEmpty && appState.lastError == nil {
                Section {
                    getStartedPrompt
                }
            }

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

            Section("Colima") {
                LabeledContent("Version") {
                    HStack(spacing: 6) {
                        Text(appState.colimaVersion ?? "…")
                            .textSelection(.enabled)
                        if let update = appState.colimaUpdateAvailable {
                            Text("→ v\(update.latestVersion) available")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                if appState.colimaUpdateAvailable != nil {
                    Text("Run `brew upgrade colima` in a terminal to update.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
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
                LabeledContent("Diagnostics") {
                    Button("Open System Log…") {
                        openWindow(id: WindowID.systemLog.rawValue)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    .buttonStyle(.link)
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

    @ViewBuilder
    private func updateNotice(_ update: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.large)
                Text("Update available")
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Spacer()
                Text("v\(update.currentVersion) → v\(update.latestVersion)")
                    .foregroundStyle(.secondary)
                    .font(.callout.monospacedDigit())
            }
            Text("Run this in a terminal to upgrade:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("brew upgrade --cask colimabar")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew upgrade --cask colimabar", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy command to clipboard")
            }
            .padding(6)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            HStack {
                Link("View release notes", destination: update.releaseURL)
                Spacer()
                Button("Skip this version") { appState.dismissUpdate() }
                    .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var getStartedPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.green)
                    .imageScale(.large)
                Text("Get started")
                    .fontWeight(.semibold)
            }
            Text("Colima is installed but has no profiles yet. Create one to boot your first VM. Sensible defaults are pre-filled — you can adjust the resources or leave them as-is.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Create your first profile…") {
                    appState.newProfileRequested = true
                }
                .keyboardShortcut(.defaultAction)
            }
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
