import SwiftUI

@main
struct ColimaBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: MenuBarIcon.build(
                cargoColor: appState.menuBarIconTint,
                showUpdateBadge: appState.updateAvailable != nil
            ))
        }
        .menuBarExtraStyle(.menu)

        Window("ColimaBar Settings", id: WindowID.settings.rawValue) {
            SettingsView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenSettingsMenuItem()
            }
        }

        Window("ColimaBar Progress", id: WindowID.progress.rawValue) {
            ProgressHUDView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Window("Container Logs", id: WindowID.containerLogs.rawValue) {
            ContainerLogsView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)

        Window("Container Inspect", id: WindowID.containerInspect.rawValue) {
            ContainerInspectView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)

        Window("Image Layers", id: WindowID.imageLayers.rawValue) {
            ImageLayersView()
                .environmentObject(appState)
        }
        .windowResizability(.contentMinSize)

        Window("ColimaBar System Log", id: WindowID.systemLog.rawValue) {
            SystemLogView()
        }
        .windowResizability(.contentMinSize)
    }
}

enum WindowID: String {
    case progress = "progress-hud"
    case settings = "settings"
    case containerLogs = "container-logs"
    case containerInspect = "container-inspect"
    case imageLayers = "image-layers"
    case systemLog = "system-log"
}

private struct OpenSettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: WindowID.settings.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
    }
}
