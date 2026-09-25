import SwiftUI

/// 「充电功率」页面（Tab 2，与「电池健康」分开显示）。
///
/// 数据全部来自前台采样（`UIDevice` 电量 + 充电状态，系统不开放第三方
/// App 读取真实充电功率瓦数，这里展示的是可观测的充电行为指标）：
/// 1. **实时充电检测**：电量环 + 充电状态 + 耗电速率 + 剩余时长 + 进行中会话进度
/// 2. **充电统计**：今日充电次数 / 平均充电时长 / 平均充电速度 / 整夜充电次数
/// 3. **充电会话**：每次「开始充电 → 结束充电」的完整记录
struct ChargingPowerView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    /// 会话按时间倒序（最新在前）
    private var sessions: [ChargingSession] {
        vm.sessions.sorted { $0.startDate > $1.startDate }
    }

    var body: some View {
        Group {
            if !vm.hasRealLevel && vm.sessions.isEmpty {
                emptyState
            } else {
                List {
                    chargingCard
                    statsSection
                    sessionsSection
                }
            }
        }
        // 液态玻璃悬浮顶栏：居中玻璃胶囊标题（无返回按钮，本页是根页面）
        .liquidGlassTopBar(title: "充电功率", showsBackButton: false)
    }

    // MARK: - 实时充电检测卡

    /// 实时电量、充电状态、耗电速率、剩余可用时长，以及进行中的充电会话。
    /// 数据来自 `BatteryMonitor` 的前台采样（模拟器/后台无数据时显示「--」）。
    private var chargingCard: some View {
        Section {
            VStack(spacing: 14) {
                // 电量环 + 状态
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.15), lineWidth: 10)
                        Circle()
                            .trim(from: 0, to: batteryLevelFraction)
                            .stroke(
                                stateGradient,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 2) {
                            Image(systemName: vm.isCharging ? "bolt.fill" : "battery.50")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(vm.isCharging ? .yellow : .green)
                            Text(batteryLevelText)
                                .font(.title2.bold())
                                .monospacedDigit()
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: 10) {
                        // 充电状态
                        Label(vm.stateText, systemImage: vm.state.symbolName)
                            .font(.headline)
                            .foregroundStyle(vm.isCharging ? .yellow : .green)
                        // 充电进度 / 耗电速率 / 剩余时长
                        if vm.isCharging {
                            if let active = vm.activeChargingSession {
                                Label("充电中 \(active.gainedPercent, format: .number.precision(.fractionLength(0)))%",
                                      systemImage: "arrow.up.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            if let rate = vm.drainRate {
                                Label("耗电 \(rate, format: .number.precision(.fractionLength(1)))%/小时",
                                      systemImage: "arrow.down.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let hours = vm.remainingHours {
                                Label("约剩 \(hours, format: .number.precision(.fractionLength(1))) 小时",
                                      systemImage: "timer")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("实时充电检测")
        }
    }

    /// 电量环填充比例（0~1；无真实电量时为 0）
    private var batteryLevelFraction: Double {
        guard vm.hasRealLevel else { return 0 }
        return min(max(vm.level, 0), 1)
    }

    /// 电量环文案（无真实电量时显示「--」）
    private var batteryLevelText: String {
        vm.levelPercent.map { "\(Int($0.rounded()))%" } ?? "--"
    }

    /// 电量环渐变色：充电黄色，放电/待机绿色
    private var stateGradient: LinearGradient {
        if vm.isCharging {
            return LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - 充电统计

    private var statsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statCell(icon: "bolt.fill", tint: .yellow,
                         title: "今日充电",
                         value: "\(BatteryAnalytics.todayChargeCount(sessions: vm.sessions))",
                         unit: "次")
                statCell(icon: "clock.fill", tint: .blue,
                         title: "平均充电时长",
                         value: avgHoursText,
                         unit: "")
                statCell(icon: "gauge.with.dots.needle.67percent", tint: .green,
                         title: "平均充电速度",
                         value: avgSpeedText,
                         unit: "")
                statCell(icon: "moon.zzz.fill", tint: .indigo,
                         title: "整夜充电",
                         value: "\(BatteryAnalytics.overnightCount(sessions: vm.sessions))",
                         unit: "次")
            }
            .padding(.vertical, 4)
        } header: {
            Text("充电统计")
        }
    }

    /// 平均充电时长文案（无数据时显示「--」）
    private var avgHoursText: String {
        guard let h = BatteryAnalytics.averageChargeHours(sessions: vm.sessions) else { return "--" }
        return String(format: "%.1f", h) + " 小时"
    }

    /// 平均充电速度文案（无数据时显示「--」）
    private var avgSpeedText: String {
        guard let s = BatteryAnalytics.averageChargeSpeed(sessions: vm.sessions) else { return "--" }
        return String(format: "%.1f", s) + " %/h"
    }

    private func statCell(icon: String, tint: Color,
                          title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 充电会话列表

    private var sessionsSection: some View {
        Section {
            if sessions.isEmpty {
                Text("暂无充电记录。连接电源开始充电后，App 会自动记录每次充电会话。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
        } header: {
            Text("充电会话（\(sessions.count) 次）")
        }
    }

    private func sessionRow(_ s: ChargingSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标题行：开始时间 + 进行中徽章
            HStack {
                Label(s.startDate.chineseDateTimeText, systemImage: "bolt.fill")
                    .font(.subheadline)
                    .foregroundStyle(s.isActive ? .yellow : .secondary)
                Spacer()
                if s.isActive {
                    Text("进行中")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.15), in: Capsule())
                        .foregroundStyle(.yellow)
                }
            }

            // 核心指标：时长 / 充入 / 速度
            HStack(spacing: 16) {
                sessionMetric("时长", s.durationText, "clock.fill")
                sessionMetric("充入", String(format: "+%.0f%%", s.gainedPercent), "arrow.up.circle.fill")
                if let speed = s.speedPercentPerHour {
                    sessionMetric("速度", String(format: "%.1f%%/小时", speed),
                                  "gauge.with.dots.needle.67percent")
                }
                Spacer(minLength: 0)
            }

            // 整夜充电标记
            if s.isOvernight {
                Label("整夜充电", systemImage: "moon.zzz.fill")
                    .font(.caption2)
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionMetric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - 空态（模拟器 / 完全无数据时）

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无充电数据").font(.headline)
            Text("连接电源开始充电后，\nApp 会自动记录充电状态、耗电速率与充电会话。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
