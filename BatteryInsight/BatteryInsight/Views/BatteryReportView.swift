import SwiftUI
import Charts

/// 周报 / 月报：把最近 7 / 30 天的健康、容量、循环、充电、温度聚合成一张摘要页。
///
/// 数据全部来自本地已采集 / 已导入的记录，不含推测值；
/// 没有数据的项显示「--」，不会编造数字。
struct BatteryReportView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    enum ReportKind: String, CaseIterable, Identifiable {
        case weekly = "周报"
        case monthly = "月报"
        var id: String { rawValue }
    }

    @State private var kind: ReportKind = .weekly
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("周期", selection: $kind) {
                        ForEach(ReportKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                reportSection(report)
            }
            // iOS 26 官方液态玻璃导航栏；sheet 内无返回按钮，左上角加关闭按钮
            .navigationTitle("周期报告")
            .navigationBarTitleDisplayMode(.inline)
                .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 40, height: 40)
                            .glassCircleBackground()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var report: BatteryReport {
        BatteryAnalytics.makeReport(
            kind: kind.rawValue,
            health: vm.healthRecords,
            analytics: vm.analyticsRecords,
            samples: vm.samples,
            sessions: vm.sessions)
    }

    @ViewBuilder
    private func reportSection(_ r: BatteryReport) -> some View {
        // 周期范围
        Section("周期（\(r.rangeText)）") {
            HStack {
                Label(r.kind, systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text(r.rangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        // 健康与容量
        Section("健康与容量") {
            healthRow(r)
            capacityRow(r)
        }

        // 循环
        Section("循环") {
            cyclesRow(r)
        }

        // 充电
        Section("充电（\(r.chargeCount) 次）") {
            if let h = r.avgChargeHours {
                valueRow("平均充电时长", valueText: String(format: "%.1f", h) + " 小时")
            }
            if let s = r.avgChargeSpeed {
                valueRow("平均充电速度", valueText: String(format: "%.1f", s) + " %/小时")
            }
            if r.overnightCount > 0 {
                valueRow("整夜充电", valueText: "\(r.overnightCount) 次")
            }
            if r.chargeCount == 0 {
                Text("本周期没有充电记录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }

        // 温度
        Section("温度") {
            if let a = r.avgTemp {
                valueRow("平均温度", valueText: String(format: "%.1f", a) + " ℃")
            }
            if let m = r.maxTemp {
                valueRow("最高温度", valueText: String(format: "%.1f", m) + " ℃")
            }
            if r.avgTemp == nil && r.maxTemp == nil {
                Text("本周期没有温度数据。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func healthRow(_ r: BatteryReport) -> some View {
        HStack {
            Label("健康度", systemImage: "heart.fill")
                .foregroundStyle(.green)
            Spacer()
            if let s = r.healthStart, let e = r.healthEnd {
                Text(String(format: "%.1f%% → %.1f%%", s, e))
                    .font(.subheadline.bold())
                if let d = r.healthDelta {
                    Text(deltaText(d, unit: "%"))
                        .font(.caption.bold())
                        .foregroundStyle(d >= 0 ? .green : .red)
                }
            } else {
                Text("--").foregroundStyle(.secondary)
            }
        }
    }

    private func capacityRow(_ r: BatteryReport) -> some View {
        HStack {
            Label("容量", systemImage: "battery.100")
                .foregroundStyle(.teal)
            Spacer()
            if let s = r.capacityStart, let e = r.capacityEnd {
                Text("\(s) → \(e) mAh")
                    .font(.subheadline.bold())
                if let d = r.capacityDelta {
                    Text(deltaText(Double(d), unit: "mAh"))
                        .font(.caption.bold())
                        .foregroundStyle(d >= 0 ? .green : .red)
                }
            } else {
                Text("--").foregroundStyle(.secondary)
            }
        }
    }

    private func cyclesRow(_ r: BatteryReport) -> some View {
        HStack {
            Label("循环次数", systemImage: "arrow.2.circlepath")
                .foregroundStyle(.blue)
            Spacer()
            if let s = r.cyclesStart, let e = r.cyclesEnd {
                Text("\(s) → \(e) 次")
                    .font(.subheadline.bold())
                if let d = r.cyclesDelta {
                    Text("+\(d) 次")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("--").foregroundStyle(.secondary)
            }
        }
    }

    private func valueRow(_ title: String, valueText: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(valueText).font(.subheadline.bold())
        }
    }

    private func deltaText(_ d: Double, unit: String) -> String {
        String(format: "%+.2f %@", d, unit)
    }
}
