import SwiftUI
import AppKit

@main
struct MareaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Preferencias — Marea", id: "prefs") {
            PreferencesView().environmentObject(state)
        }
        .windowResizability(.contentSize)
    }

    private var menuIcon: String {
        let running = state.statuses.filter { $0.runState == .running || $0.runState == .partial }.count
        return running > 0 ? "water.waves" : "drop"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // app de barra: sin icono en el Dock
        NSApp.setActivationPolicy(.accessory)
    }
}
