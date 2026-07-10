import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            MetricsView()
            Divider()
            if state.statuses.isEmpty {
                Text("Cargando…").foregroundStyle(.secondary).padding()
            } else {
                ForEach(state.statuses) { s in
                    StackRow(status: s)
                    Divider().opacity(0.4)
                }
            }
            footer
        }
        .frame(width: 380)
    }

    private var header: some View {
        HStack {
            Image(systemName: "water.waves").foregroundStyle(.teal)
            Text("Marea").font(.headline)
            Spacer()
            Text("Auto").font(.caption).foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { state.config.settings.autoMode },
                set: { state.setAutoMode($0) }
            ))
            .toggleStyle(.switch).controlSize(.small).labelsHidden()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(String(format: "swap %.0f%%", state.swapPercent), systemImage: "memorychip")
                .foregroundStyle(state.swapPercent >= state.config.settings.pressureSwapPercent ? .orange : .secondary)
            Divider().frame(height: 12)
            Label(humanBytes(state.totalDockerMem), systemImage: "shippingbox")
                .foregroundStyle(.secondary)
                .help("RAM total usada por los contenedores")
            Spacer()
            Button { state.refresh(applyActions: false) } label: {
                Image(systemName: state.busy ? "arrow.clockwise.circle" : "arrow.clockwise")
            }.buttonStyle(.borderless).help("Refrescar")
            Button {
                state.setShowWidget(!state.config.settings.showWidget)
            } label: {
                Image(systemName: state.config.settings.showWidget ? "macwindow.badge.plus" : "macwindow")
            }
                .buttonStyle(.borderless)
                .help(state.config.settings.showWidget ? "Ocultar widget de escritorio" : "Mostrar widget de escritorio")
            Button {
                openWindow(id: "prefs")
                NSApp.activate(ignoringOtherApps: true)
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless).help("Preferencias")
            Button("Salir") { NSApp.terminate(nil) }.buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct StackRow: View {
    @EnvironmentObject var state: AppState
    let status: StackStatus
    @State private var expanded = false

    private var isUp: Bool { status.runState == .running || status.runState == .partial }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if expanded {
                ForEach(status.containers) { c in ContainerRow(info: c) }
                    .padding(.leading, 30).padding(.bottom, 4)
            }
        }
    }

    private var mainRow: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() } } label: {
                Image(systemName: status.totalCount > 0 ? (expanded ? "chevron.down" : "chevron.right") : "circle.fill")
                    .font(.system(size: 9)).frame(width: 10)
                    .foregroundStyle(status.totalCount > 0 ? Color.secondary : Color.clear)
            }.buttonStyle(.borderless).disabled(status.totalCount == 0)

            Circle().fill(dotColor).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(status.config.displayName).font(.system(size: 13, weight: .medium))
                    if status.config.pinned { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.orange) }
                    if !status.config.managed { Text("manual").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                metricsLine
                if !status.procs.isEmpty { hostLine }
                HStack(spacing: 6) {
                    if status.agent != .none { agentBadge }
                    sourceBadges
                    Text(status.reason).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let o = status.orca { OrcaBadge(orca: o) }
                if let g = status.gsd { GSDBadge(gsd: g) }
            }
            Spacer()
            if !isNoDocker {
                if status.config.managed && status.shouldRun != isUp && state.config.settings.autoMode {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(.blue)
                        .help(status.shouldRun ? "prenderá" : "apagará")
                }
                Button {
                    state.setPinned(status.config, !status.config.pinned)
                } label: { Image(systemName: status.config.pinned ? "pin.slash" : "pin") }
                    .buttonStyle(.borderless).help(status.config.pinned ? "Quitar pin" : "Fijar prendido")
                Toggle("", isOn: Binding(get: { isUp }, set: { _ in state.toggle(status.config) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
    }

    private var isNoDocker: Bool { if case .none = status.config.kind { return true }; return false }

    @ViewBuilder private var metricsLine: some View {
        if isUp {
            HStack(spacing: 8) {
                Label("\(status.runningCount)/\(status.totalCount)", systemImage: "cube.box")
                Label(humanBytes(status.memBytes), systemImage: "memorychip")
                Label(String(format: "%.0f%%", status.cpuPercent), systemImage: "cpu")
                    .foregroundStyle(status.cpuPercent > 100 ? .orange : .secondary)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        } else if status.totalCount > 0 {
            Text("\(status.totalCount) contenedor(es) · apagado")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    /// Servidores host (sin Docker): puertos escuchando.
    private var hostLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.horizontal.circle").font(.system(size: 10)).foregroundStyle(.cyan)
            Text(status.procs.map { ":\($0.port)" }.joined(separator: " "))
                .font(.system(size: 10)).foregroundStyle(.cyan).lineLimit(1)
            Text("host").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    /// Badges de fuente: ~/Dev · Orca · Docker.
    private var sourceBadges: some View {
        HStack(spacing: 3) {
            if status.inDev { Image(systemName: "folder").font(.system(size: 8)).foregroundStyle(.secondary).help("~/Dev") }
            if status.orca != nil { Image(systemName: "water.waves").font(.system(size: 8)).foregroundStyle(.teal).help("Orca") }
            if status.totalCount > 0 { Image(systemName: "shippingbox").font(.system(size: 8)).foregroundStyle(.blue).help("Docker") }
        }
    }

    private var dotColor: Color {
        switch status.serverKind {
        case .docker: return .green
        case .host: return .cyan
        case .dockerOff: return .gray.opacity(0.5)
        case .none: return .gray.opacity(0.3)
        }
    }

    @ViewBuilder private var agentBadge: some View {
        switch status.agent {
        case .executing: Label("agente", systemImage: "bolt.fill").font(.system(size: 10)).foregroundStyle(.green)
        case .waiting:   Label("espera", systemImage: "hand.raised.fill").font(.system(size: 10)).foregroundStyle(.orange)
        case .idle:      Label("idle", systemImage: "moon.zzz").font(.system(size: 10)).foregroundStyle(.secondary)
        case .none:      EmptyView()
        }
    }
}

/// Badge con la info del worktree en Orca (branch, estado, PR, agentes).
struct OrcaBadge: View {
    let orca: OrcaInfo

    private var statusColor: Color {
        switch orca.workspaceStatus {
        case "in-progress": return .blue
        case "needs-review", "review": return .orange
        case "done", "completed", "merged": return .green
        case "blocked": return .red
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(.teal)
            if !orca.branch.isEmpty {
                Text(orca.branch).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .truncationMode(.middle).frame(maxWidth: 130, alignment: .leading)
            }
            if orca.unread {
                Circle().fill(.blue).frame(width: 5, height: 5)
            }
            if !orca.workspaceStatus.isEmpty {
                Text(orca.workspaceStatus).font(.system(size: 9))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            if !orca.linkedPR.isEmpty {
                Label("#\(orca.linkedPR)", systemImage: "arrow.triangle.pull")
                    .font(.system(size: 9)).foregroundStyle(.purple)
            }
            if orca.childCount > 0 {
                Label("\(orca.childCount)", systemImage: "person.2.fill")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .help("\(orca.childCount) worktree(s) hijo (agentes)")
            }
        }
    }
}

/// Badge con el estado GSD del proyecto (milestone, fase, status, progreso).
struct GSDBadge: View {
    let gsd: GSDInfo

    private var statusColor: Color {
        switch gsd.status {
        case "executing": return .green
        case "planning", "discussing": return .blue
        case "paused": return .orange
        case "complete", "done": return .teal
        default: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checklist").font(.system(size: 9)).foregroundStyle(.purple)
            if !gsd.milestone.isEmpty {
                Text(gsd.milestone).font(.system(size: 10, weight: .medium))
            }
            if !gsd.phase.isEmpty {
                Text("· Fase \(gsd.phase)").font(.system(size: 10))
                if !gsd.phaseName.isEmpty {
                    Text(gsd.phaseName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if !gsd.status.isEmpty {
                Text(gsd.status).font(.system(size: 9))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }
            if gsd.percent > 0 {
                Text("\(gsd.percent)%").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Detalle de un contenedor individual (dentro del stack expandido).
struct ContainerRow: View {
    let info: ContainerInfo

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(info.running ? Color.green : Color.gray.opacity(0.5)).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.name).font(.system(size: 11, weight: .medium))
                Text(info.image).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                if !info.ports.isEmpty {
                    Text(info.ports).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(info.status).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                if info.running {
                    HStack(spacing: 6) {
                        Text(humanBytes(info.memBytes))
                        Text(String(format: "%.0f%%", info.cpuPercent))
                            .foregroundStyle(info.cpuPercent > 100 ? .orange : .secondary)
                    }
                    .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.trailing, 12).padding(.vertical, 2)
    }
}
