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

/// Núcleo de decisión: fusiona señales de Orca + Docker + sistema.
struct Engine {
    /// Recuerda desde cuándo un stack está inactivo (anti-flapping). id -> fecha.
    private var inactiveSince: [String: Date] = [:]

    mutating func evaluate(config: Config, probes: ProbeResult, now: Date = Date()) -> [StackStatus] {
        let orca = probes.orca
        let compose = probes.compose
        let runningContainers = probes.running
        let swapPercent = probes.swap
        let underPressure = swapPercent >= config.settings.pressureSwapPercent
        let freshWindow = underPressure
            ? config.settings.freshMinutesUnderPressure
            : config.settings.freshMinutes
        let nowMs = now.timeIntervalSince1970 * 1000

        var result: [StackStatus] = []
        for stack in config.stacks {
            // --- estado real en Docker ---
            let runState = currentRunState(stack, compose: compose, running: runningContainers)

            // --- actividad en Orca (por prefijo de ruta, cubre worktrees hijos) ---
            let agent = agentState(for: stack.orcaPath, orca: orca)
            let lastOut = bestLastOutput(for: stack.orcaPath, orca: orca)
            let idleMin: Double? = lastOut.map { (nowMs - $0) / 60000 }

            // --- decisión ---
            var shouldRun: Bool
            var reason: String
            if !stack.managed {
                shouldRun = (runState == .running || runState == .partial)
                reason = "no gestionado"
            } else if stack.pinned {
                shouldRun = true
                reason = "fijado (pin)"
            } else if agent == .executing {
                shouldRun = true
                reason = "agente ejecutando"
            } else if agent == .waiting {
                shouldRun = true
                reason = "agente esperando input"
            } else if let idle = idleMin, idle < freshWindow {
                shouldRun = true
                reason = String(format: "actividad hace %.0f min", idle)
            } else if lastOut == nil && agent == .none {
                shouldRun = false
                reason = "no abierto en Orca"
            } else {
                shouldRun = false
                let idleTxt = idleMin.map { String(format: "%.0f min", $0) } ?? "—"
                reason = "idle \(idleTxt)\(underPressure ? " · RAM apretada" : "")"
            }

            // --- gracia anti-flapping (solo para apagar) ---
            if shouldRun {
                inactiveSince[stack.id] = nil
            } else {
                let since = inactiveSince[stack.id] ?? now
                inactiveSince[stack.id] = since
                let calm = now.timeIntervalSince(since) / 60
                if calm < config.settings.graceMinutes && (runState == .running || runState == .partial) {
                    // aún en periodo de gracia: no apagues todavía
                    shouldRun = true
                    reason = String(format: "gracia %.0f/%.0f min", calm, config.settings.graceMinutes)
                }
            }

            // --- métricas y detalle de Docker ---
            let names = containerNames(stack, compose: compose, probes: probes)
            let infos = names.compactMap { probes.infos[$0] }
                .sorted { $0.running && !$1.running || ($0.running == $1.running && $0.name < $1.name) }
            let running = infos.filter { $0.running }
            let cpu = running.reduce(0.0) { $0 + $1.cpuPercent }
            let mem = running.reduce(0.0) { $0 + $1.memBytes }

            result.append(StackStatus(config: stack, runState: runState, agent: agent,
                                      idleMinutes: idleMin, shouldRun: shouldRun, reason: reason,
                                      runningCount: running.count, totalCount: names.count,
                                      cpuPercent: cpu, memBytes: mem, containers: infos,
                                      gsd: probes.gsd[stack.orcaPath],
                                      orca: orcaInfo(stack.orcaPath, probes.orcaWt)))
        }
        return result
    }

    /// Nombres de contenedores que pertenecen a un stack.
    private func containerNames(_ stack: StackConfig, compose: [String: RunStateDir],
                                probes: ProbeResult) -> [String] {
        switch stack.kind {
        case .compose(let dir):
            guard let project = compose.first(where: { $0.value.dir == dir })?.key else { return [] }
            return probes.allContainers.filter { $0.value == project }.map { $0.key }
        case .standalone(let containers):
            return containers
        }
    }

    private func currentRunState(_ stack: StackConfig,
                                 compose: [String: RunStateDir],
                                 running: Set<String>) -> RunState {
        switch stack.kind {
        case .compose(let dir):
            // casa por directorio del compose
            if let match = compose.first(where: { $0.value.dir == dir })?.value { return match.state }
            return .stopped
        case .standalone(let containers):
            let up = containers.filter { running.contains($0) }.count
            if up == 0 { return .stopped }
            if up == containers.count { return .running }
            return .partial
        }
    }

    /// Info de Orca para un orcaPath: match exacto, si no, el mejor prefijo.
    private func orcaInfo(_ orcaPath: String, _ all: [String: OrcaInfo]) -> OrcaInfo? {
        if let exact = all[orcaPath] { return exact }
        return all.first(where: { $0.key.hasPrefix(orcaPath) })?.value
    }

    private func agentState(for orcaPath: String, orca: OrcaActivity) -> AgentState {
        // el más "activo" entre este path y sus hijos
        var best: AgentState = .none
        let order: [AgentState] = [.none, .idle, .waiting, .executing]
        for (path, state) in orca.agentStateByPath where path.hasPrefix(orcaPath) {
            if order.firstIndex(of: state)! > order.firstIndex(of: best)! { best = state }
        }
        if best == .none && orca.hasAgentTab.contains(where: { $0.hasPrefix(orcaPath) }) {
            best = .idle
        }
        return best
    }

    private func bestLastOutput(for orcaPath: String, orca: OrcaActivity) -> Double? {
        orca.lastOutputByPath.filter { $0.key.hasPrefix(orcaPath) }.values.max()
    }
}
