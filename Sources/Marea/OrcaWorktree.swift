import Foundation

/// Info de un worktree de Orca (para comunicar qué se está trabajando).
struct OrcaInfo: Sendable, Codable {
    var branch: String            // sin "refs/heads/"
    var workspaceStatus: String   // "in-progress" / "needs-review" / ...
    var comment: String           // resumen (a menudo el estado GSD sincronizado)
    var linkedPR: String          // número o ""
    var linkedIssue: String       // número o ""
    var unread: Bool
    var childCount: Int           // worktrees hijos = agentes en paralelo
}

enum OrcaWorktreeProbe {
    /// orcaPath -> info del worktree. Usa JSONSerialization (tolerante a tipos).
    static func read() -> [String: OrcaInfo] {
        let r = Shell.run("orca worktree list --json", timeout: 8)
        guard r.code == 0, let data = r.out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let wts = result["worktrees"] as? [[String: Any]] else { return [:] }

        var out: [String: OrcaInfo] = [:]
        for w in wts {
            guard let path = w["path"] as? String else { continue }
            let info = OrcaInfo(
                branch: (w["branch"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: ""),
                workspaceStatus: w["workspaceStatus"] as? String ?? "",
                comment: (w["comment"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                linkedPR: scalar(w["linkedPR"]),
                linkedIssue: scalar(w["linkedIssue"]),
                unread: w["isUnread"] as? Bool ?? false,
                childCount: (w["childWorktreeIds"] as? [Any])?.count ?? 0)
            // el worktree principal gana si hay varios en la misma ruta
            if out[path] == nil || (w["isMainWorktree"] as? Bool ?? false) { out[path] = info }
        }
        return out
    }

    /// Convierte un valor (Int/String/objeto con number) a texto plano.
    private static func scalar(_ v: Any?) -> String {
        if let n = v as? Int { return String(n) }
        if let s = v as? String { return s }
        if let d = v as? [String: Any], let n = d["number"] as? Int { return String(n) }
        return ""
    }
}
