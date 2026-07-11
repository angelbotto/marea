import Foundation

/// Cómo se maneja un stack en Docker.
enum StackKind: Codable, Equatable, Sendable {
    /// docker compose: se opera desde el directorio del compose file.
    case compose(dir: String)
    /// contenedores sueltos (docker run): se operan por nombre.
    case standalone(containers: [String])
    /// proyecto sin Docker (solo ~/Dev / Orca / procesos host).
    case none
}

/// Un servidor/proceso corriendo en el host (fuera de Docker).
struct HostProc: Sendable, Codable, Identifiable {
    var id: String { "\(name):\(port)" }
    var name: String
    var port: Int
    var root: String   // raíz del proyecto (resuelta del cwd)
}

/// Definición de un stack: lo que el usuario configura en ~/.config/marea/config.json
struct StackConfig: Codable, Identifiable, Equatable, Sendable {
    var id: String            // nombre único (ej. "roadmap", "cobralo")
    var displayName: String
    var kind: StackKind
    /// Ruta del worktree en Orca que representa "estoy trabajando en esto".
    var orcaPath: String
    /// Si false, Marea lo muestra pero no lo prende/apaga.
    var managed: Bool = true
    /// Si true, se mantiene siempre prendido (ignora inactividad).
    var pinned: Bool = false
}

/// Preferencias globales del motor.
struct AppSettings: Codable, Equatable, Sendable {
    /// Si true, Marea actúa (prende/apaga). Si false, solo observa y sugiere.
    var autoMode: Bool = false
    /// Minutos sin actividad para considerar un proyecto "no en uso" (RAM holgada).
    var freshMinutes: Double = 30
    /// Cuando la RAM está apretada, ventana de inactividad más corta.
    var freshMinutesUnderPressure: Double = 8
    /// Minutos de gracia continua antes de apagar (anti-flapping).
    var graceMinutes: Double = 5
    /// % de swap usado que dispara el modo "apretado".
    var pressureSwapPercent: Double = 80
    /// Segundos entre cada ciclo de observación.
    var pollSeconds: Double = 15
    /// Muestrear CPU/RAM por contenedor (docker stats). Cuesta ~1-2s por ciclo.
    var collectStats: Bool = true
    /// Mostrar el panel flotante en el escritorio.
    var showWidget: Bool = false
    /// Notificar cuando el modo Auto prende/apaga un stack.
    var notifications: Bool = true
}

extension AppSettings {
    /// Decodificación tolerante: campos ausentes usan su default (sobrevive cambios de esquema).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        autoMode = try c.decodeIfPresent(Bool.self, forKey: .autoMode) ?? d.autoMode
        freshMinutes = try c.decodeIfPresent(Double.self, forKey: .freshMinutes) ?? d.freshMinutes
        freshMinutesUnderPressure = try c.decodeIfPresent(Double.self, forKey: .freshMinutesUnderPressure) ?? d.freshMinutesUnderPressure
        graceMinutes = try c.decodeIfPresent(Double.self, forKey: .graceMinutes) ?? d.graceMinutes
        pressureSwapPercent = try c.decodeIfPresent(Double.self, forKey: .pressureSwapPercent) ?? d.pressureSwapPercent
        pollSeconds = try c.decodeIfPresent(Double.self, forKey: .pollSeconds) ?? d.pollSeconds
        collectStats = try c.decodeIfPresent(Bool.self, forKey: .collectStats) ?? d.collectStats
        showWidget = try c.decodeIfPresent(Bool.self, forKey: .showWidget) ?? d.showWidget
        notifications = try c.decodeIfPresent(Bool.self, forKey: .notifications) ?? d.notifications
    }
}

struct Config: Codable, Equatable, Sendable {
    var settings: AppSettings = AppSettings()
    var stacks: [StackConfig] = []
}

/// Estado en vivo de un contenedor/stack en Docker.
enum RunState: String, Codable, Sendable {
    case running, partial, stopped, unknown
}

/// Estado de agente para un proyecto, derivado de Orca.
enum AgentState: String, Codable, Sendable {
    case executing   // hay un agente trabajando ahora
    case waiting     // agente esperando input del usuario
    case idle        // terminó / sin agente activo
    case none        // no hay terminal de agente
}

/// La decisión del motor para un stack en un ciclo.
struct StackStatus: Identifiable, Sendable {
    var id: String { config.id }
    var config: StackConfig
    var runState: RunState
    var agent: AgentState
    var idleMinutes: Double?      // minutos desde la última actividad en Orca
    var shouldRun: Bool           // lo que el motor quiere
    var reason: String            // explicación legible
    // --- métricas de Docker en vivo ---
    var runningCount: Int = 0     // contenedores corriendo
    var totalCount: Int = 0       // contenedores del stack (corriendo + parados)
    var cpuPercent: Double = 0    // suma de CPU% de sus contenedores
    var memBytes: Double = 0      // suma de RAM usada por sus contenedores
    var containers: [ContainerInfo] = []  // detalle por contenedor
    var gsd: GSDInfo?             // estado GSD del proyecto, si aplica
    var orca: OrcaInfo?          // info del worktree en Orca, si aplica
    var procs: [HostProc] = []   // servidores host (sin Docker) del proyecto
    var inDev: Bool = false      // existe bajo ~/Dev
    var extraConfigs: [StackConfig] = []  // otros stacks Docker del mismo proyecto (dedupe)

    /// Todos los stacks Docker de este proyecto (para prender/apagar juntos).
    var allConfigs: [StackConfig] { [config] + extraConfigs }

    /// De dónde viene lo que corre.
    var serverKind: ServerKind {
        if runState == .running || runState == .partial { return .docker }
        if !procs.isEmpty { return .host }
        if totalCount > 0 { return .dockerOff }
        return .none
    }
}

enum ServerKind { case docker, host, dockerOff, none }

extension Array where Element == StackStatus {
    /// Ordena: lo que corre primero (Docker o host), luego apagado, luego sin servidor.
    func sortedRunningFirst() -> [StackStatus] {
        func rank(_ s: StackStatus) -> Int {
            switch s.serverKind {
            case .docker: return 0
            case .host: return 1
            case .dockerOff: return 2
            case .none: return 3
            }
        }
        return enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map { $0.element }
    }
}

/// Métrica puntual de un contenedor (de `docker stats`).
struct ContainerStat: Sendable {
    var cpuPercent: Double
    var memBytes: Double
}

/// Punto de métricas en el tiempo (para las gráficas del menú).
struct Sample: Identifiable, Codable, Sendable {
    var id: Date { t }
    var t: Date
    var memBytes: Double
    var cpuPercent: Double
    var swapPercent: Double
    var running: Int
}

/// Snapshot que la app escribe a disco para widgets / integraciones externas.
struct Snapshot: Codable, Sendable {
    var updatedAt: Date
    var swapPercent: Double
    var totalMemBytes: Double
    var totalCPU: Double
    var stacks: [Stack]
    var history: [Sample]

    struct Stack: Codable, Sendable {
        var id: String
        var name: String
        var running: Bool
        var runningCount: Int
        var totalCount: Int
        var memBytes: Double
        var cpuPercent: Double
        var agent: String
        var gsd: GSDInfo?
        var orca: OrcaInfo?
        var procs: [HostProc] = []
        var inDev: Bool = false
    }
}

/// Detalle de un contenedor para mostrar en el menú.
struct ContainerInfo: Sendable, Identifiable {
    var id: String { name }
    var name: String
    var image: String
    var state: String      // "running" / "exited" / ...
    var status: String     // "Up 3 days (healthy)" / "Exited (0) 2 hours ago"
    var ports: String      // "0.0.0.0:5432->5432/tcp"
    var project: String    // proyecto compose (o "")
    var running: Bool
    var cpuPercent: Double = 0
    var memBytes: Double = 0
}
