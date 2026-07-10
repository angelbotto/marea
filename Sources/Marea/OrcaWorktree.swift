import Foundation

/// Info de un proyecto en Orca (agregada de sus worktrees).
struct OrcaInfo: Sendable, Codable {
    var branch: String            // sin "refs/heads/"
    var workspaceStatus: String   // "in-progress" / "needs-review" / ...
    var comment: String
    var linkedPR: String
    var linkedIssue: String
    var unread: Bool
    var childCount: Int           // worktrees extra (agentes en paralelo)
}

/// Resultado del probe de Orca: info por raíz + mapa de rutas → raíz.
struct OrcaData: Sendable {
    var byRoot: [String: OrcaInfo] = [:]       // raíz del proyecto → info
    var wtPathToRoot: [String: String] = [:]   // cualquier worktree path → raíz
    var roots: [String] = []                   // raíces abiertas en Orca
}

enum OrcaWorktreeProbe {
    static func read() -> OrcaData {
        let r = Shell.run("orca worktree list --json", timeout: 8)
        var data = OrcaData()
        guard r.code == 0, let bytes = r.out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let wts = result["worktrees"] as? [[String: Any]] else { return data }

        // agrupar worktrees por repoId
        var byRepo: [String: [[String: Any]]] = [:]
        for w in wts {
            let repo = (w["repoId"] as? String) ?? (w["path"] as? String ?? "")
            byRepo[repo, default: []].append(w)
        }

        for (_, group) in byRepo {
            // raíz del proyecto = worktree principal (path bajo ~/Dev)
            let mainWt = group.first(where: { ($0["isMainWorktree"] as? Bool) ?? false }) ?? group[0]
            guard let rootPath = mainWt["path"] as? String else { continue }
            // primario para mostrar = uno en progreso/revisión, si no el principal
            let primary = group.first(where: {
                let s = $0["workspaceStatus"] as? String ?? ""
                return s == "in-progress" || s == "in-review"
            }) ?? mainWt

            data.byRoot[rootPath] = OrcaInfo(
                branch: (primary["branch"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: ""),
                workspaceStatus: primary["workspaceStatus"] as? String ?? "",
                comment: (primary["comment"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                linkedPR: scalar(primary["linkedPR"]),
                linkedIssue: scalar(primary["linkedIssue"]),
                unread: group.contains { ($0["isUnread"] as? Bool) ?? false },
                childCount: max(0, group.count - 1))
            data.roots.append(rootPath)
            for w in group { if let p = w["path"] as? String { data.wtPathToRoot[p] = rootPath } }
        }
        return data
    }

    private static func scalar(_ v: Any?) -> String {
        if let n = v as? Int { return String(n) }
        if let s = v as? String { return s }
        if let d = v as? [String: Any], let n = d["number"] as? Int { return String(n) }
        return ""
    }
}
