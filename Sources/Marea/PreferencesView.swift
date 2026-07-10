import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var state: AppState
    @State private var loginEnabled = LoginItem.isEnabled

    var body: some View {
        TabView {
            behaviorTab.tabItem { Label("Comportamiento", systemImage: "gearshape") }
            stacksTab.tabItem { Label("Stacks", systemImage: "square.stack.3d.up") }
            aboutTab.tabItem { Label("Acerca de", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 440)
        .padding()
    }

    // MARK: Acerca de

    private var aboutTab: some View {
        VStack(spacing: 14) {
            Image(systemName: "water.waves")
                .font(.system(size: 52)).foregroundStyle(.teal)
                .padding(.top, 8)
            Text(About.name).font(.system(size: 24, weight: .bold))
            Text("versión \(About.version)").font(.caption).foregroundStyle(.secondary)
            Text(About.tagline)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 320)

            Divider().frame(width: 220)

            Toggle(isOn: Binding(
                get: { loginEnabled },
                set: { newVal in
                    if LoginItem.setEnabled(newVal) { loginEnabled = newVal }
                    else { loginEnabled = LoginItem.isEnabled }
                })) {
                Label("Abrir al iniciar sesión", systemImage: "power")
            }
            .toggleStyle(.switch)
            .help("Requiere que Marea esté en /Applications")

            Spacer()
            VStack(spacing: 2) {
                Text("Hecho por \(About.author) · \(About.year)").font(.system(size: 11))
                Text("Construido con Claude Code").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
        .onAppear { loginEnabled = LoginItem.isEnabled }
    }

    // MARK: Comportamiento

    private var behaviorTab: some View {
        Form {
            Section("Motor") {
                Toggle("Modo automático (prender/apagar solo)", isOn: binding(\.autoMode))
                Toggle("Muestrear CPU/RAM por contenedor", isOn: binding(\.collectStats))
                Toggle("Notificar al prender/apagar", isOn: binding(\.notifications))
            }
            Section("Inactividad") {
                stepper("Apagar tras (min) sin actividad", \.freshMinutes, 5...240, 5)
                stepper("Con RAM apretada, apagar tras (min)", \.freshMinutesUnderPressure, 1...120, 1)
                stepper("Gracia anti-flapping (min)", \.graceMinutes, 0...30, 1)
            }
            Section("Sistema") {
                stepper("Umbral de swap para 'RAM apretada' (%)", \.pressureSwapPercent, 30...99, 5)
                stepper("Refrescar cada (seg)", \.pollSeconds, 5...120, 5)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Stacks

    private var stacksTab: some View {
        VStack(alignment: .leading) {
            Text("Un stack por proyecto. `Orca path` = la ruta del worktree que representa 'estoy trabajando en esto'.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(state.config.stacks.indices, id: \.self) { idx in
                    stackEditor(idx)
                }
            }
        }
    }

    @ViewBuilder private func stackEditor(_ idx: Int) -> some View {
        let stack = state.config.stacks[idx]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("Nombre", text: Binding(
                    get: { state.config.stacks[idx].displayName },
                    set: { state.config.stacks[idx].displayName = $0; state.saveConfig() }))
                .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("Gestionado", isOn: Binding(
                    get: { state.config.stacks[idx].managed },
                    set: { state.config.stacks[idx].managed = $0; state.saveConfig() }))
                .controlSize(.small)
            }
            HStack {
                Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
                TextField("Orca path", text: Binding(
                    get: { state.config.stacks[idx].orcaPath },
                    set: { state.config.stacks[idx].orcaPath = $0; state.saveConfig() }))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(kindLabel(stack.kind)).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private func kindLabel(_ kind: StackKind) -> String {
        switch kind {
        case .compose(let dir): return "compose · \(dir)"
        case .standalone(let c): return "standalone · \(c.joined(separator: ", "))"
        case .none: return "sin Docker"
        }
    }

    // MARK: helpers de binding

    private func binding(_ kp: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { state.config.settings[keyPath: kp] },
                set: { state.config.settings[keyPath: kp] = $0; state.saveConfig() })
    }

    private func stepper(_ title: String, _ kp: WritableKeyPath<AppSettings, Double>,
                         _ range: ClosedRange<Double>, _ step: Double) -> some View {
        Stepper(value: Binding(
            get: { state.config.settings[keyPath: kp] },
            set: { state.config.settings[keyPath: kp] = $0; state.saveConfig() }),
                in: range, step: step) {
            HStack { Text(title); Spacer()
                Text(String(format: "%.0f", state.config.settings[keyPath: kp]))
                    .foregroundStyle(.secondary).monospacedDigit() }
        }
    }
}
