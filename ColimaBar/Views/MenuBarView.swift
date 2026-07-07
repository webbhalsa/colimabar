import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let update = appState.updateAvailable {
            Button {
                appState.selectGeneralRequested = true
                openWindow(id: WindowID.settings.rawValue)
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
            if appState.lastError == nil {
                Button {
                    appState.newProfileRequested = true
                    openWindow(id: WindowID.settings.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Start your first profile…", systemImage: "plus.circle.fill")
                }
            } else {
                Text("No colima profiles")
            }
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
                        Button("Open Terminal…") {
                            appState.openTerminalInVM(profileName: profile.name)
                        }
                        Button("Copy DOCKER_HOST") {
                            appState.copyDockerHost(for: profile)
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
            Task {
                await appState.refresh()
                await appState.refreshDiskUsage()
            }
        }
        .keyboardShortcut("r")

        Button("Settings…") {
            openWindow(id: WindowID.settings.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("System Log…") {
            openWindow(id: WindowID.systemLog.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("l")

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
