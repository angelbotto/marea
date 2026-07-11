import SwiftUI
import AppKit

@main
struct MareaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(state)
        } label: {
            Image(nsImage: StatusIcon.image)
        }
        .menuBarExtraStyle(.window)

        Window("Preferencias — Marea", id: "prefs") {
            PreferencesView().environmentObject(state)
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // app de barra: sin icono en el Dock
        NSApp.setActivationPolicy(.accessory)
        // restaurar el widget de escritorio si estaba visible
        if AppState.shared.config.settings.showWidget {
            WidgetPanelController.shared.show()
        }
    }
}
