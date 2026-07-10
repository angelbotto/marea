import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var config: Config
    @Published var statuses: [StackStatus] = []
    @Published var swapPercent: Double = 0
    @Published var lastSync: Date?
    @Published var busy = false
    /// Historial de métricas para las gráficas (últimas ~15 min).
    @Published var history: [Sample] = []

    private var engine = Engine()
    private var timer: Timer?
    private let maxSamples = 60

    /// RAM total usada por todos los contenedores gestionados (bytes).
    var totalDockerMem: Double { statuses.reduce(0) { $0 + $1.memBytes } }
    var totalDockerCPU: Double { statuses.reduce(0) { $0 + $1.cpuPercent } }

    init() {
        self.config = ConfigStore.load()
        if config.settings.notifications { Notifier.requestAuthorization() }
        scheduleTimer()
        refresh()
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(5, config.settings.pollSeconds),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Un ciclo: observa (fuera del main), decide (en el main), y si autoMode, aplica.
    func refresh(applyActions: Bool? = nil) {
        guard !busy else { return }
        busy = true
        let cfg = config
        let apply = applyActions ?? cfg.settings.autoMode
        let withStats = cfg.settings.collectStats
        let orcaPaths = cfg.stacks.map { $0.orcaPath }
        Task {
            let probes = await Task.detached { Probes.gather(withStats: withStats, orcaPaths: orcaPaths) }.value
            let statuses = engine.evaluate(config: cfg, probes: probes).sortedRunningFirst()
            if apply {
                let acts = statuses.filter { $0.config.managed }.compactMap { s -> (Bool, StackStatus)? in
                    let isUp = (s.runState == .running || s.runState == .partial)
                    if s.shouldRun && !isUp { return (true, s) }
                    if !s.shouldRun && isUp { return (false, s) }
                    return nil
                }
                if !acts.isEmpty {
                    let cfgs = acts.map { ($0.0, $0.1.config) }
                    await Task.detached { cfgs.forEach { applyDocker(up: $0.0, $0.1) } }.value
                    if cfg.settings.notifications {
                        for (up, s) in acts {
                            if up {
                                Notifier.notify(title: "🟢 Prendí \(s.config.displayName)", body: s.reason)
                            } else {
                                Notifier.notify(title: "⚪ Apagué \(s.config.displayName)",
                                                body: "\(s.reason) → liberé \(humanBytes(s.memBytes))")
                            }
                        }
                    }
                }
            }
            self.statuses = statuses
            self.swapPercent = probes.swap
            self.lastSync = Date()
            self.busy = false
            self.recordSample()
            self.writeSnapshot()
        }
    }

    /// Guarda un punto de métricas para las gráficas.
    private func recordSample() {
        let s = Sample(t: Date(), memBytes: totalDockerMem, cpuPercent: totalDockerCPU,
                       swapPercent: swapPercent, running: statuses.filter {
                           $0.runState == .running || $0.runState == .partial }.count)
        history.append(s)
        if history.count > maxSamples { history.removeFirst(history.count - maxSamples) }
    }

    /// Escribe un snapshot JSON (~/.config/marea/snapshot.json) para widgets / integraciones.
    private func writeSnapshot() {
        let snap = Snapshot(
            updatedAt: Date(),
            swapPercent: swapPercent,
            totalMemBytes: totalDockerMem,
            totalCPU: totalDockerCPU,
            stacks: statuses.map {
                Snapshot.Stack(id: $0.id, name: $0.config.displayName,
                               running: $0.runState == .running || $0.runState == .partial,
                               runningCount: $0.runningCount, totalCount: $0.totalCount,
                               memBytes: $0.memBytes, cpuPercent: $0.cpuPercent,
                               agent: $0.agent.rawValue, gsd: $0.gsd, orca: $0.orca,
                               procs: $0.procs, inDev: $0.inDev)
            },
            history: history)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        guard let data = try? enc.encode(snap) else { return }
        // 1) ~/.config/marea/snapshot.json (integraciones / debug)
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/marea/snapshot.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        // 2) contenedor del App Group (lo lee el widget de WidgetKit); nil si no hay entitlement
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) {
            try? data.write(to: group.appendingPathComponent("snapshot.json"))
            WidgetBridge.reload()
        }
    }

    /// Acción manual desde el menú (prende/apaga ya).
    func toggle(_ stack: StackConfig) {
        let isUp = statuses.first(where: { $0.id == stack.id })
            .map { $0.runState == .running || $0.runState == .partial } ?? false
        busy = true
        Task {
            await Task.detached { applyDocker(up: !isUp, stack) }.value
            self.busy = false
            self.refresh(applyActions: false)
        }
    }

    func setPinned(_ stack: StackConfig, _ pinned: Bool) {
        guard let i = config.stacks.firstIndex(where: { $0.id == stack.id }) else { return }
        config.stacks[i].pinned = pinned
        ConfigStore.save(config)
        refresh(applyActions: false)
    }

    func setAutoMode(_ on: Bool) {
        config.settings.autoMode = on
        ConfigStore.save(config)
    }

    /// Muestra/oculta el widget de escritorio y persiste la preferencia.
    func setShowWidget(_ on: Bool) {
        config.settings.showWidget = on
        ConfigStore.save(config)
        on ? WidgetPanelController.shared.show() : WidgetPanelController.shared.hide()
    }

    /// Persiste cambios hechos en Preferencias y reprograma el timer.
    func saveConfig() {
        ConfigStore.save(config)
        scheduleTimer()
        refresh(applyActions: false)
    }
}

/// Aplica una acción de Docker. Libre de actor: solo llama a Shell.
func applyDocker(up: Bool, _ stack: StackConfig) {
    switch stack.kind {
    case .compose(let dir):
        up ? DockerProbe.composeUp(dir: dir) : DockerProbe.composeStop(dir: dir)
    case .standalone(let containers):
        for c in containers { up ? DockerProbe.start(container: c) : DockerProbe.stop(container: c) }
    case .none:
        break
    }
}

/// Formatea bytes a una cadena legible (MB/GB).
func humanBytes(_ bytes: Double) -> String {
    if bytes <= 0 { return "0" }
    if bytes >= 1_073_741_824 { return String(format: "%.1f GB", bytes / 1_073_741_824) }
    if bytes >= 1_048_576 { return String(format: "%.0f MB", bytes / 1_048_576) }
    return String(format: "%.0f KB", bytes / 1024)
}
