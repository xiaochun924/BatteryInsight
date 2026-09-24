import SwiftUI

/// 概览页：当前电量环、核心指标、数据操作
struct DashboardView: View {
    @EnvironmentObject private var vm: BatteryViewModel

    /// 「更多」入口：概览页右上角跳转到健康 / 建议 / 日志等次要页面
    @State private var showingMore = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    batteryRing
                    metricsGrid

                    if !vm.hasData {
                        startHint
                    } else if !vm.hasRealLevel {
                        simulatorHint
                    }

                    dataSection
                }
                .padding()
                .padding(.bottom, 8)
            }
            .navigationTitle("电池概览")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingMore = true } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingMore) { moreSheet }
        }
    }

    /// 次要功能统一收进这里，主 Tab 保持 4 个，避免被收纳进系统「More」
    private var moreSheet: some View {
        NavigationStack {
            List {
                Section("分析") {
                    NavigationLink {
                        HealthView()
                    } label: {
                        Label("电池健康", systemImage: "heart.fill")
                    }
                    NavigationLink {
                        AnalyticsView()
                    } label: {
                        Label("日志分析", systemImage: "doc.text.magnifyingglass")
                    }
                }
                Section("保养") {
                    NavigationLink {
                        TipsView()
                    } label: {
                        Label("优化建议", systemImage: "lightbulb.fill")
                    }
                }
            }
            .navigationTitle("更多")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingMore = false }
                }
            }
        }
    }

    // MARK: - 电量环

    private var batteryRing: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 18)
                .opacity(0.15)
                .foregroundStyle(ringColor)

            Circle()
                .trim(from: 0, to: max(0, min(1, vm.level)))
                .stroke(style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .foregroundStyle(ringColor)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: vm.level)

            VStack(spacing: 4) {
                if let percent = vm.levelPercent {
                    Text("\(Int(percent))%")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: "questionmark").font(.largeTitle)
                    Text("不可用").font(.caption)
                }
                HStack(spacing: 4) {
                    Image(systemName: vm.state.symbolName)
                    Text(vm.stateText)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 180)
        .padding(.top, 8)
    }

    private var ringColor: Color {
        if vm.isCharging { return .green }
        guard let percent = vm.levelPercent else { return .gray }
        if percent <= 20 { return .red }
        if percent <= 40 { return .orange }
        return .blue
    }

    // MARK: - 指标

    private var metricsGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricCard(title: "耗电速率", value: rateText, unit: "%/小时",
                       icon: "hare.fill", tint: .orange)
            MetricCard(title: "预计可用", value: remainText, unit: "小时",
                       icon: "clock.fill", tint: .blue)
            MetricCard(title: "今日耗电", value: todayDrainText, unit: "%",
                       icon: "arrow.down.right", tint: .purple)
            MetricCard(title: "今日充电", value: "\(BatteryAnalytics.todayChargeCount(sessions: vm.sessions))",
                       unit: "次", icon: "bolt.fill", tint: .green)
        }
    }

    private var rateText: String {
        guard let rate = vm.drainRate else { return "--" }
        return String(format: "%.1f", rate)
    }

    private var remainText: String {
        guard let hours = vm.remainingHours else { return "--" }
        return String(format: "%.1f", hours)
    }

    private var todayDrainText: String {
        guard let drain = BatteryAnalytics.todayDrainPercent(vm.samples) else { return "--" }
        return String(format: "%.0f", drain)
    }

    // MARK: - 提示与操作

    private var startHint: some View {
        HintCard(icon: "iphone", title: "暂无采样数据") {
            Text("本 App 读取系统电量并在前台定时采样（默认 60 秒一次）。真机上会自动开始记录；模拟器中系统不提供电池数据，可先载入演示数据查看完整界面。")
        }
    }

    private var simulatorHint: some View {
        HintCard(icon: "exclamationmark.circle", title: "当前设备读不到电量") {
            Text("模拟器不提供电池信息（电量返回 -1）。请在真机上运行以采集真实数据，或载入演示数据预览效果。")
        }
    }

    private var dataSection: some View {
        VStack(spacing: 10) {
            Button { vm.loadDemoData() } label: {
                Label("载入演示数据", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) { vm.clearAll() } label: {
                Label("清空全部数据", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }
}

// MARK: - 可复用组件

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title2.bold())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct HintCard<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            content
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
