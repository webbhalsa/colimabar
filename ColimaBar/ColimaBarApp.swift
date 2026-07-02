import SwiftUI

@main
struct ColimaBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: MenuBarIcon.build(cargoColor: appState.menuBarIconTint))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("ColimaBar Progress", id: WindowID.progress.rawValue) {
            ProgressHUDView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

enum WindowID: String {
    case progress = "progress-hud"
}
