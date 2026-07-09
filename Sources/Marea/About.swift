import Foundation
import ServiceManagement

/// Metadatos de la app (para créditos y compartir).
enum About {
    static let name = "Marea"
    static let tagline = "Prende y apaga tus stacks de Docker según lo que trabajas en Orca."
    static let author = "Angel Botto"
    static let year = "2026"
    static let repo = ""   // opcional: URL del repo si se publica

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (v, b) {
        case let (v?, b?): return "\(v) (\(b))"
        case let (v?, nil): return v
        default: return "dev"
        }
    }
}

/// Arranque al iniciar sesión (ServiceManagement). Requiere app empaquetada (.app).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Devuelve true si el cambio se aplicó.
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            NSLog("Marea: no se pudo cambiar el login item: \(error.localizedDescription)")
            return false
        }
    }
}
