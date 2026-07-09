import SwiftUI
import AppKit

/// Controla el panel flotante (widget de escritorio) hecho con NSPanel.
@MainActor
final class WidgetPanelController {
    static let shared = WidgetPanelController()
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 300),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            p.hidesOnDeactivate = false
            p.isMovableByWindowBackground = true
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isOpaque = false
            p.contentView = NSHostingView(rootView: WidgetView().environmentObject(AppState.shared))
            if let vf = NSScreen.main?.visibleFrame {
                p.setFrameOrigin(NSPoint(x: vf.maxX - 280, y: vf.maxY - 320))
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

/// Contenido del widget de escritorio: métricas + stacks activos.
struct WidgetView: View {
    @EnvironmentObject var state: AppState

    private var active: [StackStatus] {
        state.statuses.filter { $0.runState == .running || $0.runState == .partial }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "water.waves").foregroundStyle(.teal)
                Text("Marea").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(String(format: "swap %.0f%%", state.swapPercent))
                    .font(.system(size: 10))
                    .foregroundStyle(state.swapPercent >= state.config.settings.pressureSwapPercent ? .orange : .secondary)
                Button { WidgetPanelController.shared.hide(); state.setShowWidget(false) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.borderless)
            }
            MetricsView().padding(.horizontal, -12)   // reusa las sparklines
            Divider()
            if active.isEmpty {
                Text("Nada corriendo").font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)
            } else {
                ForEach(active) { s in
                    HStack(spacing: 6) {
                        Circle().fill(s.runState == .running ? Color.green : Color.yellow)
                            .frame(width: 7, height: 7)
                        Text(s.config.displayName).font(.system(size: 11)).lineLimit(1)
                        if s.agent == .executing {
                            Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(.green)
                        }
                        Spacer()
                        Text(humanBytes(s.memBytes)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 260)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.08)))
    }
}
