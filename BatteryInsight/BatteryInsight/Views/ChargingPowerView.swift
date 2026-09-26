import SwiftUI

/// 「充电功率」页面（Tab 2，与「电池健康」分开显示）。
///
/// iOS 不开放第三方 App 读取真实充电功率瓦数，这里用「可观测数据估算 + 日志实测」：
/// 1. **充电功率检测**：当前功率（充电速度 × 电池容量 × 标称电压 估算）
///    + 最大充电功率（分析日志实测：峰值充电电流 × 峰值电压）
struct ChargingPowerView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    var body: some View {
        Group {
            if vm.latestAnalytics == nil && !vm.sessions.contains(where: { $0.isActive }) {
                emptyState
            } else {
                List {
                    powerSection
                }
            }
        }
        // 液态玻璃悬浮顶栏：居中玻璃胶囊标题（无返回按钮，本页是根页面）
        .liquidGlassTopBar(title: "充电功率", showsBackButton: false)
    }

    // MARK: - 充电功率检测

    /// 当前充电速度（%/小时）：进行中的会话实时计算；无进行中会话时回退到历史平均
    private var currentChargeSpeed: Double? {
        if vm.isCharging, let active = vm.activeChargingSession {
            let hours = active.duration / 3600
            if hours >= 0.02 {
                return active.gainedPercent / hours
            }
        }
        return BatteryAnalytics.averageChargeSpeed(sessions: vm.sessions)
    }

    /// 电池容量（mAh）：优先日志额定容量，其次机型出厂容量
    private var batteryCapacityMah: Int? {
        vm.latestAnalytics?.nominalChargeCapacity ?? DeviceBatterySpec.current?.factoryCapacity
    }

    /// 当前充电功率估算（W）= 容量(Ah) × 标称电压(V) × 充电速度(%/h) ÷ 100。
    /// iPhone 锂电池标称电压 3.85V；系统不开放真实功率，只能按此口径估算。
    private var currentPowerWatts: Double? {
        guard let speed = currentChargeSpeed,
              let mah = batteryCapacityMah, mah > 0 else { return nil }
        return Double(mah) / 1000 * 3.85 * speed / 100
    }

    /// 当前功率文案（未充电 / 数据不足时显示「--」）
    private var currentPowerText: String {
        guard vm.isCharging, let w = currentPowerWatts else { return "--" }
        return String(format: "%.1f", w)
    }

    /// 充电速度文案
    private var chargeSpeedText: String {
        guard let s = currentChargeSpeed else { return "--" }
        return String(format: "%.1f %/h", s)
    }

    /// 最大充电功率（日志实测：峰值充电电流 × 峰值电压）
    private var maxChargePowerText: String? {
        guard let r = vm.latestAnalytics,
              let m = DerivedMetrics.maxChargePower(from: r) else { return nil }
        return m.valueText
    }

    private var powerSection: some View {
        Section {
            VStack(spacing: 12) {
                // 当前充电功率大数字
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(currentPowerText)
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(vm.isCharging ? Color.yellow : Color.secondary)
                    Text("W")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if vm.isCharging {
                        Text("估算中")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.yellow.opacity(0.15), in: Capsule())
                            .foregroundStyle(.yellow)
                    }
                }

                Divider()

                HStack {
                    Label("充电速度", systemImage: "speedometer")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(chargeSpeedText)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
                HStack {
                    Label("最大充电功率（日志实测）", systemImage: "bolt.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(maxChargePowerText ?? "--")
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("充电功率检测")
        } footer: {
            Text("iOS 不开放实时功率读取：当前功率 = 充电速度 × 电池容量 × 标称电压(3.85V) 估算；最大功率来自分析日志实测（峰值充电电流 × 峰值电压）。")
        }
    }

    // MARK: - 空态（模拟器 / 完全无数据时）

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.badge.clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("暂无充电数据").font(.headline)
            Text("连接电源开始充电后，\nApp 会自动记录充电状态与耗电速率。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
