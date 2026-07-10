import Foundation

/// Carga/guarda ~/.config/marea/config.json
enum ConfigStore {
    static var url: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/marea/config.json")
    }

    static func load() -> Config {
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let seed = seedConfig()
        save(seed)
        return seed
    }

    static func save(_ cfg: Config) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) { try? data.write(to: url) }
    }

    /// Semilla con el mapeo detectado en el entorno del usuario.
    static func seedConfig() -> Config {
        let home = NSHomeDirectory()
        let stacks: [StackConfig] = [
            StackConfig(id: "roadmap", displayName: "Roadmap (Kova)",
                        kind: .compose(dir: "\(home)/Dev/liftit/roadmap"),
                        orcaPath: "\(home)/Dev/liftit/roadmap"),
            StackConfig(id: "cobralo", displayName: "Cobralo",
                        kind: .compose(dir: "\(home)/Dev/cobralo/docker"),
                        orcaPath: "\(home)/Dev/cobralo"),
            StackConfig(id: "aeon", displayName: "Aeon (beu)",
                        kind: .compose(dir: "\(home)/Dev/beu/aeon"),
                        orcaPath: "\(home)/Dev/beu/aeon"),
            StackConfig(id: "aegon", displayName: "Aegon infra",
                        kind: .compose(dir: "\(home)/Dev/liftit/aegon/infra"),
                        orcaPath: "\(home)/Dev/liftit/aegon"),
            StackConfig(id: "plane", displayName: "Plane (taskis)",
                        kind: .compose(dir: "\(home)/Dev/liftit/taskis/plane"),
                        orcaPath: "\(home)/Dev/liftit/taskis/plane"),
            StackConfig(id: "osrm", displayName: "OSRM Colombia (vaekor)",
                        kind: .standalone(containers: ["vaekor-osrm-colombia"]),
                        orcaPath: "\(home)/Dev/liftit/vaekor"),
            StackConfig(id: "twenty", displayName: "Twenty CRM",
                        kind: .standalone(containers: ["twenty-app-dev"]),
                        orcaPath: "\(home)/Dev/hacks/ostigard", managed: false),
        ]
        return Config(settings: AppSettings(), stacks: stacks)
    }
}

/// Núcleo de decisión: fusiona señales de ~/Dev + Orca + Docker + procesos.
struct Engine {
    /// Recuerda desde cuándo un stack está inactivo (anti-flapping). id -> fecha.
    private var inactiveSince: [String: Date] = [:]

    mutating func evaluate(config: Config, probes: ProbeResult, now: Date = Date()) -> [StackStatus] {
        let underPressure = probes.swap >= config.settings.pressureSwapPercent
        let freshWindow = underPressure
            ? config.settings.freshMinutesUnderPressure
            : config.settings.freshMinutes
        let nowMs = now.timeIntervalSince1970 * 1000
        let home = NSHomeDirectory()

        // --- resolver: cualquier ruta -> raíz de proyecto ---
        let knownRoots = Set(config.stacks.map { $0.orcaPath })
            .union(probes.orcaData.roots).union(probes.devRoots)
        func resolve(_ path: String) -> String? {
            for (wt, root) in probes.orcaData.wtPathToRoot where path == wt || path.hasPrefix(wt + "/") {
                return root
            }
            return knownRoots.filter { path == $0 || path.hasPrefix($0 + "/") }
                .max(by: { $0.count < $1.count })
        }

        // --- procesos host agrupados por raíz de proyecto ---
        var procsByRoot: [String: [HostProc]] = [:]
        for p in probes.procs {
            guard let root = resolve(p.cwd) else { continue }
            let hp = HostProc(name: p.name, port: p.port, root: root)
            if !(procsByRoot[root]?.contains { $0.id == hp.id } ?? false) {
                procsByRoot[root, default: []].append(hp)
            }
        }

        // --- señales de agente / actividad, agregadas por raíz (vía resolver) ---
        let order: [AgentState] = [.none, .idle, .waiting, .executing]
        var agentByRoot: [String: AgentState] = [:]
        for (path, state) in probes.orca.agentStateByPath {
            guard let root = resolve(path) else { continue }
            let cur = agentByRoot[root] ?? .none
            if order.firstIndex(of: state)! > order.firstIndex(of: cur)! { agentByRoot[root] = state }
        }
        for path in probes.orca.hasAgentTab {
            guard let root = resolve(path) else { continue }
            if (agentByRoot[root] ?? .none) == .none { agentByRoot[root] = .idle }
        }
        var lastOutByRoot: [String: Double] = [:]
        for (path, ts) in probes.orca.lastOutputByPath {
            guard let root = resolve(path) else { continue }
            lastOutByRoot[root] = max(lastOutByRoot[root] ?? 0, ts)
        }

        // --- construir items: stacks de config + proyectos descubiertos ---
        var result: [StackStatus] = []
        var covered = Set<String>()
        for stack in config.stacks {
            result.append(build(stack, config: config, probes: probes, now: now, nowMs: nowMs,
                                 freshWindow: freshWindow, underPressure: underPressure,
                                 procs: procsByRoot[stack.orcaPath] ?? [],
                                 agent: agentByRoot[stack.orcaPath] ?? .none,
                                 lastOut: lastOutByRoot[stack.orcaPath], home: home))
            covered.insert(stack.orcaPath)
        }
        // proyectos abiertos en Orca o con servidor host, sin stack en config
        let discovered = Set(probes.orcaData.roots).union(procsByRoot.keys).subtracting(covered)
        for root in discovered {
            let name = (root as NSString).lastPathComponent
            let synth = StackConfig(id: "auto:\(root)", displayName: name, kind: .none,
                                    orcaPath: root, managed: false)
            result.append(build(synth, config: config, probes: probes, now: now, nowMs: nowMs,
                                freshWindow: freshWindow, underPressure: underPressure,
                                procs: procsByRoot[root] ?? [],
                                agent: agentByRoot[root] ?? .none,
                                lastOut: lastOutByRoot[root], home: home))
        }
        return result
    }

    private mutating func build(_ stack: StackConfig, config: Config, probes: ProbeResult,
                                now: Date, nowMs: Double, freshWindow: Double, underPressure: Bool,
                                procs: [HostProc], agent: AgentState, lastOut: Double?,
                                home: String) -> StackStatus {
        let runState = currentRunState(stack, compose: probes.compose, running: probes.running)
        let idleMin: Double? = lastOut.map { (nowMs - $0) / 60000 }
        let isUp = (runState == .running || runState == .partial)

        var shouldRun: Bool
        var reason: String
        if case .none = stack.kind {
            shouldRun = false
            reason = procs.isEmpty ? "solo en Orca / ~/Dev" : "servidor host"
        } else if !stack.managed {
            shouldRun = isUp; reason = "no gestionado"
        } else if stack.pinned {
            shouldRun = true; reason = "fijado (pin)"
        } else if agent == .executing {
            shouldRun = true; reason = "agente ejecutando"
        } else if agent == .waiting {
            shouldRun = true; reason = "agente esperando input"
        } else if let idle = idleMin, idle < freshWindow {
            shouldRun = true; reason = String(format: "actividad hace %.0f min", idle)
        } else if lastOut == nil && agent == .none {
            shouldRun = false; reason = "no abierto en Orca"
        } else {
            shouldRun = false
            let t = idleMin.map { String(format: "%.0f min", $0) } ?? "—"
            reason = "idle \(t)\(underPressure ? " · RAM apretada" : "")"
        }

        // gracia anti-flapping (solo para apagar Docker)
        if shouldRun {
            inactiveSince[stack.id] = nil
        } else if isUp {
            let since = inactiveSince[stack.id] ?? now
            inactiveSince[stack.id] = since
            let calm = now.timeIntervalSince(since) / 60
            if calm < config.settings.graceMinutes {
                shouldRun = true
                reason = String(format: "gracia %.0f/%.0f min", calm, config.settings.graceMinutes)
            }
        }

        let names = containerNames(stack, compose: probes.compose, probes: probes)
        let infos = names.compactMap { probes.infos[$0] }
            .sorted { ($0.running && !$1.running) || ($0.running == $1.running && $0.name < $1.name) }
        let running = infos.filter { $0.running }
        return StackStatus(config: stack, runState: runState, agent: agent,
                           idleMinutes: idleMin, shouldRun: shouldRun, reason: reason,
                           runningCount: running.count, totalCount: names.count,
                           cpuPercent: running.reduce(0) { $0 + $1.cpuPercent },
                           memBytes: running.reduce(0) { $0 + $1.memBytes },
                           containers: infos,
                           gsd: probes.gsd[stack.orcaPath],
                           orca: probes.orcaData.byRoot[stack.orcaPath],
                           procs: procs.sorted { $0.port < $1.port },
                           inDev: stack.orcaPath.hasPrefix(home + "/Dev"))
    }

    private func containerNames(_ stack: StackConfig, compose: [String: RunStateDir],
                                probes: ProbeResult) -> [String] {
        switch stack.kind {
        case .compose(let dir):
            guard let project = compose.first(where: { $0.value.dir == dir })?.key else { return [] }
            return probes.allContainers.filter { $0.value == project }.map { $0.key }
        case .standalone(let containers):
            return containers
        case .none:
            return []
        }
    }

    private func currentRunState(_ stack: StackConfig, compose: [String: RunStateDir],
                                 running: Set<String>) -> RunState {
        switch stack.kind {
        case .compose(let dir):
            if let match = compose.first(where: { $0.value.dir == dir })?.value { return match.state }
            return .stopped
        case .standalone(let containers):
            let up = containers.filter { running.contains($0) }.count
            if up == 0 { return .stopped }
            return up == containers.count ? .running : .partial
        case .none:
            return .stopped
        }
    }
}
