import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let update = appState.updateAvailable {
            Button {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Update to v\(update.latestVersion)", systemImage: "arrow.down.circle.fill")
            }
            Divider()
        }

        if let error = appState.lastError, appState.profiles.isEmpty {
            Text(error)
            Divider()
        }

        if appState.profiles.isEmpty {
            Text("No colima profiles")
        } else {
            ForEach(appState.profiles) { profile in
                Section(header: Text(profile.name)) {
                    Text(statusSummary(profile))

                    if profile.status == .running {
                        Button("Stop") {
                            appState.beginStop(profile)
                            showProgress()
                        }
                        Button("Restart") {
                            appState.beginRestart(profile)
                            showProgress()
                        }
                    } else {
                        Button("Start") {
                            appState.beginStart(profile)
                            showProgress()
                        }
                    }
                }
            }
        }

        if appState.runningOperation != nil {
            Divider()
            Button("Show Progress…") { showProgress() }
                .keyboardShortcut("p")
        }

        Divider()

        Button("Refresh") {
            Task { await appState.refresh() }
        }
        .keyboardShortcut("r")

        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit ColimaBar") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func statusSummary(_ p: Profile) -> String {
        "\(p.status.rawValue) · \(p.cpu) CPU · \(p.memoryGB) GB · \(p.runtime)"
    }

    private func showProgress() {
        openWindow(id: WindowID.progress.rawValue)
        NSApp.activate(ignoringOtherApps: true)
    }
}
