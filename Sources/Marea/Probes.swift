import Foundation

/// Ejecuta comandos vía login shell (resuelve PATH: docker, orca, etc.).
enum Shell {
    @discardableResult
    static func run(_ command: String, timeout: TimeInterval = 20) -> (out: String, code: Int32) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return ("", -1) }

        // watchdog para no colgar el ciclo
        let deadline = DispatchWorkItem { if proc.isRunning { proc.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        deadline.cancel()
        return (String(data: data, encoding: .utf8) ?? "", proc.terminationStatus)
    }
}

// MARK: - Orca

struct OrcaActivity: Sendable {
    /// worktreePath -> última actividad (epoch ms)
    var lastOutputByPath: [String: Double] = [:]
    /// worktreePath -> hay pestaña de agente viva
    var hasAgentTab: Set<String> = []
    /// worktreePath -> estado de agente derivado de last-status.json
    var agentStateByPath: [String: AgentState] = [:]
}

/// Resultado de un ciclo de observación (cruza actores => Sendable).
struct ProbeResult: Sendable {
    var orca: OrcaActivity
    var compose: [String: RunStateDir]
    var running: Set<String>
    var swap: Double
    /// todos los contenedores conocidos (corriendo o parados) -> proyecto
    var allContainers: [String: String] = [:]
    /// nombre de contenedor -> detalle completo (con CPU/RAM si withStats)
    var infos: [String: ContainerInfo] = [:]
    /// orcaPath -> estado GSD del proyecto (si usa GSD)
    var gsd: [String: GSDInfo] = [:]
    /// datos de Orca agrupados por raíz de proyecto
    var orcaData: OrcaData = OrcaData()
    /// procesos host escuchando puertos (servidores con/sin Docker)
    var procs: [RawProc] = []
    /// raíces de proyecto bajo ~/Dev
    var devRoots: [String] = []
}

struct RunStateDir: Sendable {
    var state: RunState
    var dir: String
}

enum OrcaProbe {
    static var lastStatusURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Orca/agent-hooks/last-status.json")
    }

    /// Extrae la ruta del worktree de un worktreeId con formato "repoId::/ruta".
    static func pathFromWorktreeId(_ id: String) -> String? {
        guard let range = id.range(of: "::") else { return nil }
        return String(id[range.upperBound...])
    }

    static func probe() -> OrcaActivity {
        var activity = OrcaActivity()

        // 1) terminales vivas (necesita runtime de Orca abierto)
        let terms = Shell.run("orca terminal list --json", timeout: 8)
        if terms.code == 0, let data = terms.out.data(using: .utf8) {
            struct Resp: Decodable { struct Result: Decodable { let terminals: [Term] }; let result: Result }
            struct Term: Decodable {
                let worktreePath: String
                let lastOutputAt: Double?
                let title: String?
            }
            if let resp = try? JSONDecoder().decode(Resp.self, from: data) {
                for t in resp.result.terminals {
                    if let ts = t.lastOutputAt {
                        activity.lastOutputByPath[t.worktreePath] =
                            max(activity.lastOutputByPath[t.worktreePath] ?? 0, ts)
                    }
                    if (t.title ?? "").contains("Claude") || (t.title ?? "").contains("Codex") {
                        activity.hasAgentTab.insert(t.worktreePath)
                    }
                }
            }
        }

        // 2) estado de agentes (persistido por los hooks; se lee aunque el runtime esté cerrado)
        if let data = try? Data(contentsOf: lastStatusURL) {
            struct Store: Decodable { let entries: [String: Entry] }
            struct Entry: Decodable {
                let worktreeId: String?
                let hookEventName: String?
                let receivedAt: Double?
                let payload: Payload?
                struct Payload: Decodable { let state: String? }
            }
            if let store = try? JSONDecoder().decode(Store.self, from: data) {
                // por worktree, la entrada más reciente gana
                var latest: [String: Entry] = [:]
                for e in store.entries.values {
                    guard let wid = e.worktreeId, let path = pathFromWorktreeId(wid) else { continue }
                    if (latest[path]?.receivedAt ?? 0) <= (e.receivedAt ?? 0) { latest[path] = e }
                }
                let now = Date().timeIntervalSince1970 * 1000
                for (path, e) in latest {
                    let event = e.hookEventName ?? ""
                    let state = e.payload?.state ?? ""
                    let ageMin = (now - (e.receivedAt ?? 0)) / 60000
                    let terminal = ["Stop", "StopFailure"].contains(event) || state == "done"
                    if terminal {
                        activity.agentStateByPath[path] = .idle
                    } else if event == "Notification" || state == "waiting" {
                        activity.agentStateByPath[path] = .waiting
                    } else if ageMin < 3 {
                        // evento no terminal y reciente => trabajando
                        activity.agentStateByPath[path] = .executing
                    } else {
                        activity.agentStateByPath[path] = .idle
                    }
                }
            }
        }
        return activity
    }
}

// MARK: - Docker

enum DockerProbe {
    /// project name -> RunState + dir del compose, leyendo `docker compose ls`.
    static func composeStates() -> [String: RunStateDir] {
        var result: [String: RunStateDir] = [:]
        let r = Shell.run("docker compose ls --all --format json", timeout: 10)
        guard r.code == 0, let data = r.out.data(using: .utf8) else { return [:] }
        struct Row: Decodable { let Name: String; let Status: String; let ConfigFiles: String }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [:] }
        for row in rows {
            // ConfigFiles = ".../proyecto/docker-compose.yml"; el dir del stack es su carpeta.
            let file = row.ConfigFiles.split(separator: ",").first.map(String.init) ?? ""
            let dirPath = (file as NSString).deletingLastPathComponent
            let state: RunState
            if row.Status.contains("exited") && row.Status.contains("running") { state = .partial }
            else if row.Status.contains("running") { state = .running }
            else { state = .stopped }
            result[row.Name] = RunStateDir(state: state, dir: dirPath)
        }
        return result
    }

    /// Todos los contenedores (corriendo o parados) con su detalle.
    static func containers() -> [ContainerInfo] {
        let fmt = "{{.Names}}\t{{.Image}}\t{{.State}}\t{{.Status}}\t{{.Ports}}\t{{.Label \"com.docker.compose.project\"}}"
        let r = Shell.run("docker ps -a --format '\(fmt)'", timeout: 10)
        guard r.code == 0 else { return [] }
        var list: [ContainerInfo] = []
        for line in r.out.split(separator: "\n") {
            let f = line.components(separatedBy: "\t")
            guard f.count >= 6, !f[0].isEmpty else { continue }
            list.append(ContainerInfo(name: f[0], image: f[1], state: f[2], status: f[3],
                                      ports: f[4], project: f[5], running: f[2] == "running"))
        }
        return list
    }

    /// nombre de contenedor -> métrica en vivo (CPU%, RAM en bytes).
    static func stats() -> [String: ContainerStat] {
        let r = Shell.run("docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'", timeout: 15)
        guard r.code == 0 else { return [:] }
        var map: [String: ContainerStat] = [:]
        for line in r.out.split(separator: "\n") {
            let p = line.split(separator: "\t")
            guard p.count >= 3 else { continue }
            let name = String(p[0])
            let cpu = Double(p[1].replacingOccurrences(of: "%", with: "")) ?? 0
            // MemUsage = "1.521GiB / 7.75GiB" -> primer valor a bytes
            let usedStr = p[2].split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            map[name] = ContainerStat(cpuPercent: cpu, memBytes: parseBytes(usedStr))
        }
        return map
    }

    /// "1.5GiB" / "512MiB" / "20.4kB" -> bytes.
    static func parseBytes(_ s: String) -> Double {
        let units: [(String, Double)] = [
            ("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1024),
            ("GB", 1_000_000_000), ("MB", 1_000_000), ("kB", 1000), ("B", 1)
        ]
        for (u, mult) in units where s.hasSuffix(u) {
            let num = s.dropLast(u.count).trimmingCharacters(in: .whitespaces)
            return (Double(num) ?? 0) * mult
        }
        return 0
    }

    static func composeUp(dir: String) { Shell.run("cd \(dir.shellQuoted) && docker compose up -d", timeout: 120) }
    static func composeStop(dir: String) { Shell.run("cd \(dir.shellQuoted) && docker compose stop", timeout: 60) }
    static func start(container: String) { Shell.run("docker start \(container.shellQuoted)", timeout: 60) }
    static func stop(container: String) { Shell.run("docker stop \(container.shellQuoted)", timeout: 60) }
}

// MARK: - Sistema (presión de memoria)

enum SystemProbe {
    /// % de swap usado (0-100).
    static func swapUsedPercent() -> Double {
        let r = Shell.run("sysctl -n vm.swapusage", timeout: 5)
        // formato: total = 24576.00M  used = 16718.50M  free = 1713.50M ...
        func mb(_ label: String) -> Double? {
            guard let range = r.out.range(of: "\(label) = ") else { return nil }
            let tail = r.out[range.upperBound...]
            let num = tail.prefix { $0.isNumber || $0 == "." }
            return Double(num)
        }
        guard let total = mb("total"), let used = mb("used"), total > 0 else { return 0 }
        return used / total * 100
    }
}

extension String {
    var shellQuoted: String { "'" + replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// Un ciclo de observación completo (se corre fuera del main thread).
enum Probes {
    static func gather(withStats: Bool, orcaPaths: [String] = []) -> ProbeResult {
        var list = DockerProbe.containers()
        if withStats {
            let stats = DockerProbe.stats()
            for i in list.indices {
                if let s = stats[list[i].name] {
                    list[i].cpuPercent = s.cpuPercent
                    list[i].memBytes = s.memBytes
                }
            }
        }
        let running = Set(list.filter { $0.running }.map { $0.name })
        var allContainers: [String: String] = [:]
        var infos: [String: ContainerInfo] = [:]
        for c in list { allContainers[c.name] = c.project; infos[c.name] = c }
        let orcaData = OrcaWorktreeProbe.read()
        let devRoots = ProjectProbe.devRoots()
        // GSD para la unión de raíces (config + Orca + ~/Dev)
        var gsd: [String: GSDInfo] = [:]
        for path in Set(orcaPaths).union(orcaData.roots).union(devRoots) {
            if let info = GSDProbe.read(path) { gsd[path] = info }
        }
        return ProbeResult(orca: OrcaProbe.probe(),
                           compose: DockerProbe.composeStates(),
                           running: running,
                           swap: SystemProbe.swapUsedPercent(),
                           allContainers: allContainers,
                           infos: infos,
                           gsd: gsd,
                           orcaData: orcaData,
                           procs: ProcessProbe.read(),
                           devRoots: devRoots)
    }
}
