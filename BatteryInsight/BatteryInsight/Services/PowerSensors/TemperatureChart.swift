import Charts
import SwiftUI

/// 最近三分钟的最高温曲线（来自 `PowerMonitor.live`）。
struct LiveTemperatureChart: View {
    let samples: [LiveSample]
    var height: CGFloat = 110

    private var points: [LiveSample] {
        samples.filter { ($0.hottestTemperature ?? .nan).isFinite }
    }

    private var domain: ClosedRange<Double> {
        let values = points.compactMap(\.hottestTemperature)
        guard let low = values.min(), let high = values.max(), low.isFinite, high.isFinite else {
            return 20...50
        }
        let padding = max((high - low) * 0.3, 1.5)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        Chart(points) { sample in
            AreaMark(x: .value("Time", sample.date),
                     y: .value("°C", sample.hottestTemperature ?? 0))
                .foregroundStyle(LinearGradient(colors: [Color.mwLoss.opacity(0.35), Color.mwLoss.opacity(0.02)],
                                                startPoint: .top,
                                                endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Time", sample.date),
                     y: .value("°C", sample.hottestTemperature ?? 0))
                .foregroundStyle(Color.mwLoss)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: domain)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.mwGrid)
                AxisValueLabel {
                    if let celsius = value.as(Double.self) {
                        Text(String(format: "%.0f°", celsius)).mwMono(size: 9).foregroundStyle(Color.mwMuted)
                    }
                }
            }
        }
        .frame(height: height)
        .clipped()
    }
}
