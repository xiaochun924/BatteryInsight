import SwiftUI

/// 充电分析页：会话统计 + 每次充电记录
struct ChargingView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    private var sorted: [ChargingSession] {
        vm.sessions.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.sessions.isEmpty {
                    emptyState
                } else {
                    List {
                        Section("整体统计") { statsGrid }
                        Section("充电记录") {
                            ForEach(sorted) { session in
                                SessionRow(session: session)
                            }
                        }
                    }
                }
            }
            .navigationTitle("充电分析")
        }
    }

    private var statsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "充电次数", value: "\(vm.sessions.count)", unit: "次",
                       icon: "bolt.fill", tint: .green)
            MetricCard(title: "平均时长", value: avgHoursText, unit: "小时",
                       icon: "clock.fill", tint: .blue)
            MetricCard(title: "平均速度", value: avgSpeedText, unit: "%/小时",
                       icon: "speedometer", tint: .orange)
            MetricCard(title: "整夜充电", value: "\(BatteryAnalytics.overnightCount(sessions: vm.sessions))",
                       unit: "次", icon: "moon.zzz.fill", tint: .indigo)
        }
        .padding(.vertical, 4)
    }

    private var avgHoursText: String {
        guard let hours = BatteryAnalytics.averageChargeHours(sessions: vm.sessions) else { return "--" }
        return String(format: "%.1f", hours)
    }

    private var avgSpeedText: String {
        guard let speed = BatteryAnalytics.averageChargeSpeed(sessions: vm.sessions) else { return "--" }
        return String(format: "%.0f", speed)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无充电记录").font(.headline)
            Text("当设备从未充电转为充电时会自动记录一次会话。由于 iOS 会挂起后台，长时间不开 App 的充电可能记录不到。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let session: ChargingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: session.isOvernight ? "moon.zzz.fill" : "bolt.fill")
                    .foregroundStyle(session.isOvernight ? .indigo : .green)
                Text(session.startDateText)
                    .font(.subheadline)
                Spacer()
                if session.isActive {
                    Text("进行中")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 14) {
                Label(session.durationText, systemImage: "clock")
                Label(String(format: "+%.0f%%", session.gainedPercent), systemImage: "arrow.up")
                if let speed = session.speedPercentPerHour {
                    Label(String(format: "%.0f%%/小时", speed), systemImage: "speedometer")
                }
                if session.isOvernight {
                    Label("整夜", systemImage: "moon.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
