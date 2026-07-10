import WidgetKit
import SwiftUI

struct MareaEntry: TimelineEntry {
    let date: Date
    let snapshot: WSnapshot?
}

struct MareaProvider: TimelineProvider {
    func placeholder(in context: Context) -> MareaEntry {
        MareaEntry(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (MareaEntry) -> Void) {
        completion(MareaEntry(date: Date(), snapshot: WidgetStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MareaEntry>) -> Void) {
        let entry = MareaEntry(date: Date(), snapshot: WidgetStore.read())
        let next = Calendar.current.date(byAdding: .minute, value: 2, to: Date()) ?? Date().addingTimeInterval(120)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct MareaWidgetView: View {
    var entry: MareaEntry
    @Environment(\.widgetFamily) var family

    private var running: [WStack] { entry.snapshot?.stacks.filter { $0.isRunning } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "water.waves").foregroundStyle(.teal)
                Text("Marea").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let s = entry.snapshot {
                    Text("swap \(Int(s.swapPercent))%")
                        .font(.system(size: 10))
                        .foregroundStyle(s.swapPercent >= 80 ? .orange : .secondary)
                }
            }
            if let s = entry.snapshot {
                HStack(spacing: 12) {
                    stat("RAM", widgetHumanBytes(s.totalMemBytes), .teal)
                    stat("CPU", String(format: "%.0f%%", s.totalCPU), s.totalCPU > 100 ? .orange : .green)
                    stat("Activos", "\(running.count)", .secondary)
                }
                Divider()
                if running.isEmpty {
                    Text("Nada corriendo").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(running.prefix(family == .systemLarge ? 7 : 3)) { st in
                        HStack(spacing: 5) {
                            Circle().fill(.green).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 4) {
                                    Text(st.name).font(.system(size: 11)).lineLimit(1)
                                    if let g = st.gsd, !g.milestone.isEmpty {
                                        Text(g.phase.isEmpty ? g.milestone : "\(g.milestone)·F\(g.phase)")
                                            .font(.system(size: 9)).foregroundStyle(.purple)
                                    }
                                }
                                if let o = st.orca, !o.branch.isEmpty {
                                    Text(o.branch).font(.system(size: 9)).foregroundStyle(.teal).lineLimit(1)
                                }
                            }
                            Spacer()
                            if st.memBytes <= 0, let ps = st.procs, !ps.isEmpty {
                                Text(ps.map { ":\($0.port)" }.joined(separator: " "))
                                    .font(.system(size: 9)).foregroundStyle(.cyan).monospacedDigit().lineLimit(1)
                            } else {
                                Text(widgetHumanBytes(st.memBytes)).font(.system(size: 10))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
            } else {
                Spacer()
                Text("Abre Marea para ver datos").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(color).monospacedDigit()
        }
    }
}

struct MareaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MareaWidget", provider: MareaProvider()) { entry in
            if #available(macOS 14.0, *) {
                MareaWidgetView(entry: entry).containerBackground(.background, for: .widget)
            } else {
                MareaWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Marea")
        .description("Estado de tus stacks de Docker y fase GSD.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct MareaWidgetBundle: WidgetBundle {
    var body: some Widget { MareaWidget() }
}
