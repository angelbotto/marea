import Foundation

// Estructuras mínimas para decodificar snapshot.json que escribe la app.

struct WSnapshot: Codable {
    var updatedAt: Date
    var swapPercent: Double
    var totalMemBytes: Double
    var totalCPU: Double
    var stacks: [WStack]
    var history: [WSample]
}

struct WStack: Codable, Identifiable {
    var id: String
    var name: String
    var running: Bool
    var runningCount: Int
    var totalCount: Int
    var memBytes: Double
    var cpuPercent: Double
    var agent: String
    var gsd: WGSD?
    var orca: WOrca?
}

struct WOrca: Codable {
    var branch: String
    var workspaceStatus: String
    var linkedPR: String
    var childCount: Int
}

struct WGSD: Codable {
    var milestone: String
    var milestoneName: String
    var phase: String
    var phaseName: String
    var status: String
    var percent: Int
}

struct WSample: Codable {
    var t: Date
    var memBytes: Double
    var cpuPercent: Double
    var swapPercent: Double
    var running: Int
}

/// Lee el snapshot del contenedor del App Group.
enum WidgetStore {
    static let groupID = "group.is.botto.marea"

    static func read() -> WSnapshot? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else { return nil }
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("snapshot.json")) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WSnapshot.self, from: data)
    }
}

func widgetHumanBytes(_ bytes: Double) -> String {
    if bytes >= 1_073_741_824 { return String(format: "%.1f GB", bytes / 1_073_741_824) }
    if bytes >= 1_048_576 { return String(format: "%.0f MB", bytes / 1_048_576) }
    return bytes > 0 ? String(format: "%.0f KB", bytes / 1024) : "0"
}
