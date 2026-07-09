import Foundation
import WidgetKit

/// Identificador del App Group compartido entre la app y el widget.
enum AppGroup {
    static let id = "group.is.botto.marea"
}

/// Pide a WidgetKit que refresque el widget cuando hay datos nuevos.
enum WidgetBridge {
    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
