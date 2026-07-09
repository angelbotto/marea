import Foundation

/// Estado de un proyecto GSD (get-shit-done), leído de `.planning/STATE.md`.
struct GSDInfo: Sendable, Codable {
    var milestone: String       // "v1.2"
    var milestoneName: String   // "Pivot híbrido"
    var phase: String           // "22"
    var phaseName: String       // "Home Body Pixel-Perfect Fix"
    var status: String          // "executing" / "planning" / "paused" / ...
    var percent: Int            // progreso del milestone
}

enum GSDProbe {
    /// Lee `<dir>/.planning/STATE.md` si existe. nil si el proyecto no usa GSD.
    static func read(_ dir: String) -> GSDInfo? {
        let planning = (dir as NSString).appendingPathComponent(".planning")
        let statePath = (planning as NSString).appendingPathComponent("STATE.md")
        guard let text = try? String(contentsOfFile: statePath, encoding: .utf8) else { return nil }

        // extraer el frontmatter YAML (entre los primeros dos "---")
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "---") else { return nil }
        var fm: [String: String] = [:]
        for line in lines[(start + 1)...] {
            if line == "---" { break }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            var val = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            val = val.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !key.isEmpty && !val.isEmpty { fm[key] = val }
        }

        let phase = fm["current_phase"] ?? ""
        let milestone = fm["milestone"] ?? ""
        // el campo `status` a veces es una frase larga; lo dejamos solo si es corto/keyword
        let rawStatus = fm["status"] ?? ""
        let status = rawStatus.count <= 24 ? rawStatus : ""
        let percent = Int(fm["percent"] ?? "") ?? 0

        // formato viejo / sin datos GSD útiles => no mostrar badge
        if milestone.isEmpty && status.isEmpty && phase.isEmpty && percent == 0 { return nil }

        return GSDInfo(
            milestone: milestone,
            milestoneName: fm["milestone_name"] ?? "",
            phase: phase,
            phaseName: phaseName(planning: planning, phase: phase),
            status: status,
            percent: percent)
    }

    /// Deriva un nombre legible de la fase desde el directorio `phases/NN-slug`.
    private static func phaseName(planning: String, phase: String) -> String {
        guard !phase.isEmpty else { return "" }
        let phasesDir = (planning as NSString).appendingPathComponent("phases")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: phasesDir) else { return "" }
        guard let dir = entries.first(where: { $0.hasPrefix("\(phase)-") }) else { return "" }
        let slug = String(dir.dropFirst(phase.count + 1)).replacingOccurrences(of: "-", with: " ")
        return slug.prefix(1).uppercased() + slug.dropFirst()
    }
}
