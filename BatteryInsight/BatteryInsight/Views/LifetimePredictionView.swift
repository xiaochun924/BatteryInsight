import SwiftUI
import Charts

/// 寿命预测页（主页趋势卡「详情」进入）。
/// 参考竞品截图布局：
/// - 顶部环状预测图：一圈弧线 + 中心大数字「2年9个月」+ 副标题「预计还需充电 500 次」
/// - 三条说明卡：每块一条（当前健康度 / 预计寿命 / 充电周期）
/// - 底部「生成周期报告」按钮（右侧小箭头 + 前往报告页）
/// 数据口径统一走 BatteryAnalytics（与主页/趋势页同源，不再各自实现一套）。
struct LifetimePredictionView: View {
    /// API-2：@Observable 环境注入（替代 @EnvironmentObject）
    @Environment(BatteryViewModel.self) private var vm

    @Environment(\.dismiss) private var dismiss
    @State private var showingReport = false

    // MARK: - 数据（只算一次，见 P0-3）

    /// P0-3：原实现 forecast 是计算属性，body 及子视图每次访问都会
    /// 重新执行整条计算链（排序、算率、算月数）。这里在 body 顶部取一次，
    /// 子视图全部改为传参函数，避免重复计算。
    private let forecast = LifetimePredictionView.makeForecast()

    /// 静态工厂：不持有视图状态也能在 body 外部计算一次
    private static func makeForecast() -> BatteryAnalytics.LifetimeForecast? {
        BatteryAnalytics.lifetimeForecast(records: DataStore.shared.healthRecords)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ringCard(forecast)
                infoCards(forecast)
                reportButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        // 液态玻璃悬浮顶栏（参考 home-inventory 官方 Liquid Glass 实现）
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            GlassTopBar(title: "寿命预测",
                        leading: { GlassCircleButton(icon: "chevron.left") { dismiss() } })
        }
        .navigationDestination(isPresented: $showingReport) { BatteryReportView() }
        // 系统导航栏已隐藏，手动恢复右滑返回手势（统一组件，见 Components.swift）
        .swipeToDismiss(dismiss)
    }

    // MARK: - 环状预测图

    private func ringCard(_ forecast: BatteryAnalytics.LifetimeForecast?) -> some View {
        // 圆环角度：进度环只有 2/3 圈（240°），留出缺口更像"目标进度"而非满环表盘
        let ringLength: Double = 240
        // 剩余寿命占出厂寿命的比例 → 弧长；nil 时兜底 0（数据不足显示 0%）
        let progress = forecast.map { clamp01($0.remainingYears / $0.factoryYears) } ?? 0
        return VStack(spacing: 12) {
            ZStack {
                // 底环（浅色）
                Circle()
                    .stroke(.quaternary, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 180, height: 180)
                // 前景环（绿色渐变，从底部逆时针走 240°）
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [.green.opacity(0.35), .green],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(150)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 180, height: 180)
                    .animation(.easeInOut(duration: 0.8), value: progress)

                VStack(spacing: 4) {
                    if let forecast {
                        Text(forecast.durationText)
                            .font(.title.bold())
                        Text("预计还需充电 \(forecast.remainingCycles) 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("--")
                            .font(.title.bold())
                        Text("数据不足，无法预测")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 200)

            HStack(spacing: 24) {
                legendItem("健康度", String(format: "%.1f%%", forecast?.currentHealth ?? 0))
                legendItem("出厂寿命", forecast?.durationText ?? "--")
                legendItem("预计寿命", forecast?.durationText ?? "--")
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func legendItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }

    // MARK: - 三条说明卡

    private func infoCards(_ forecast: BatteryAnalytics.LifetimeForecast?) -> some View {
        // 用数组 + ForEach 渲染三条（比手写三个 VStack 更易维护）
        let items: [(icon: String, tint: Color, title: String, text: String)] = [
            ("battery.100", .green, "当前健康度",
             forecast.map { String(format: "%.1f%%", $0.currentHealth) } ?? "--"),
            ("hourglass", .orange, "预计寿命",
             forecast.map { "\($0.durationText)（还需充电 \($0.remainingCycles) 次）" } ?? "--"),
            ("arrow.2.circlepath", .blue, "充电周期",
             "预计 \(forecast.map { "\($0.remainingCycles)" } ?? "--") 次"),
        ]
        return VStack(spacing: 12) {
            ForEach(items, id: \.title) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.title3)
                        .foregroundStyle(item.tint)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(item.text)
                            .font(.subheadline.bold())
                    }
                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .cardStyle()
            }
        }
    }

    // MARK: - 生成周期报告

    private var reportButton: some View {
        Button { showingReport = true } label: {
            HStack {
                Text("生成周期报告")
                    .font(.subheadline.bold())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            // 与上方卡片一致的磨砂玻璃白底（按钮也是卡片，保持同一视觉层级）
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
}

// MARK: - 卡片样式（H-2 重构后：统一走 Components.swift 的 CardContainer）

/// 本页卡片统一使用 Components.swift 的 CardContainer：
/// 圆角 16 continuous + 磨砂玻璃白底 + 系统分隔线描边。
/// 各页面各自实现的卡片样式已收敛到该组件（见 Components.swift 顶部注释）。
private extension View {
    func cardStyle() -> some View {
        self.modifier(CardContainerModifier())
    }
}
