import SwiftUI
import Charts

/// Panel compacto de métricas con sparklines (RAM y CPU de Docker en el tiempo).
struct MetricsView: View {
    @EnvironmentObject var state: AppState

    private var memGB: Double { state.totalDockerMem / 1_073_741_824 }

    var body: some View {
        HStack(spacing: 10) {
            metric(title: "RAM Docker",
                   value: humanBytes(state.totalDockerMem),
                   color: .teal) { s in s.memBytes / 1_073_741_824 }
            Divider().frame(height: 42)
            metric(title: "CPU Docker",
                   value: String(format: "%.0f%%", state.totalDockerCPU),
                   color: state.totalDockerCPU > 100 ? .orange : .green) { s in s.cpuPercent }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func metric(title: String, value: String, color: Color,
                        _ y: @escaping (Sample) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .semibold)).monospacedDigit()
            sparkline(color: color, y: y)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sparkline(color: Color, y: @escaping (Sample) -> Double) -> some View {
        if state.history.count >= 2 {
            Chart(state.history) { s in
                AreaMark(x: .value("t", s.t), y: .value("v", y(s)))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("t", s.t), y: .value("v", y(s)))
                    .foregroundStyle(color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartLegend(.hidden)
        } else {
            RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.4))
                .overlay(Text("recolectando…").font(.system(size: 8)).foregroundStyle(.tertiary))
        }
    }
}
