import SwiftUI
import Charts

/// 主页：实时电量 + 充电会话 + 健康趋势 + 今日用电概览
struct BatteryHomeView: View {
    @ObservedObject var viewModel: BatteryViewModel
    @State private var showingReport = false
    @State private var reportKind = "周报"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    levelCard
                    if viewModel.hasRealLevel {
                        statsRow
                    }
                    tipsSection
                    if !viewModel.samples.isEmpty {
                        batteryTrendSection
                        todaySection
                    }
                    chargingSection
                    healthSection
                    if !viewModel.sessions.isEmpty {
                        sessionsSection
                    }
                }
                .padding()
            }
            .navigationTitle("电池")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.loadDemoData()
                        } label: {
                            Label("载入示例数据", systemImage: "wand.and.stars")
                        }
                        Divider()
                        Button {
                            reportKind = "周报"
                            showingReport = true
                        } label: {
                            Label("周报", systemImage: "calendar")
                        }
                        Button {
                            reportKind = "月报"
                            showingReport = true
                        } label: {
                            Label("月报", systemImage: "calendar.badge.clock")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingReport) {
                BatteryReportView(kind: reportKind, viewModel: viewModel)
            }
        }
    }

    // MARK: - 实时电量

    private var levelCard: some View {
        VStack(spacing: 8) {
            Text(viewModel.hasRealLevel ? "当前电量" : "实时电量")
                .font(.headline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: viewModel.hasRealLevel ? CGFloat(min(viewModel.level, 1.0)) : 0.75)
                    .stroke(
                        viewModel.isCharging ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    if let pct = viewModel.levelPercent {
                        Text("\(Int(pct.rounded()))%")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text("--")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                    }
                    Text(viewModel.stateText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)
            .padding(.vertical, 8)

            HStack(spacing: 16) {
                Label("已用 \(viewModel.todayDrainPercent ?? 0, specifier: "%.0f")%",
                      systemImage: "battery.25")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 统计行

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell("今日充电", "\(viewModel.todayChargeCount(sessions: viewModel.sessions)) 次",
                     systemImage: "bolt.fill", tint: .green)
            statCell("今日耗电", viewModel.todayDrainPercent.map { "\(Int($0.rounded()))%" } ?? "--",
                     systemImage: "battery.25", tint: .blue)
            statCell("平均充电速度", viewModel.averageChargeSpeed(sessions: viewModel.sessions).map {
                "\(Int($0.rounded()))%/h" } ?? "--",
                     systemImage: "speedometer", tint: .orange)
        }
    }

    private func statCell(_ title: String, _ value: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 建议

    private var tipsSection: some View {
        Group {
            if !viewModel.tips.isEmpty {
                VStack(spacing: 12) {
                    ForEach(viewModel.tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tip.icon)
                                .foregroundStyle(tip.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                    .font(.subheadline.weight(.medium))
                                Text(tip.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(
                            tip.tint.opacity(0.08)))
                    }
                }
            }
        }
    }

    // MARK: - 趋势图

    private var batteryTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("电量趋势")
                    .font(.headline)
                Spacer()
                Text("最近 24 小时")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(Array(viewModel.samples.suffix(96).enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("时间", sample.date),
                        y: .value("电量", sample.level * 100),
                        series: .value("series", "电量"))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...100)
            .frame(height: 160)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 今日概览

    private var todaySection: some View {
        let today = viewModel.todaySamples(samples: viewModel.samples)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今日概览")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 12) {
                statCell("起始电量", today.first.map { "\(Int(($0.level * 100).rounded()))%" } ?? "--",
                         systemImage: "sunrise", tint: .orange)
                statCell("当前电量", viewModel.levelPercent.map { "\(Int($0.rounded()))%" } ?? "--",
                         systemImage: "sun.max", tint: .yellow)
                statCell("充电次数", "\(viewModel.todayChargeCount(sessions: viewModel.sessions)) 次",
                         systemImage: "bolt", tint: .green)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 充电会话

    private var chargingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("充电数据")
                    .font(.headline)
                Spacer()
            }
            HStack(spacing: 12) {
                statCell("充电总次数", "\(viewModel.sessions.count)",
                         systemImage: "bolt.heart", tint: .green)
                statCell("平均充电时长", viewModel.averageChargeHours(sessions: viewModel.sessions).map {
                    String(format: "%.1f h", $0) } ?? "--",
                         systemImage: "timer", tint: .blue)
                statCell("平均充电速度", viewModel.averageChargeSpeed(sessions: viewModel.sessions).map {
                    "\(Int($0.rounded()))%/h" } ?? "--",
                         systemImage: "gauge", tint: .orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 健康

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("电池健康")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    HealthDetailView(viewModel: viewModel)
                } label: {
                    Text("详情")
                        .font(.subheadline)
                }
            }
            if let latest = viewModel.latestHealth(records: viewModel.healthRecords) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最大容量")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(String(format: "%.0f", latest.maximumCapacity))%")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                    Spacer()
                    if let months = viewModel.monthsUntil80(records: viewModel.healthRecords) {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("预计降至 80%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("约 \(String(format: "%.0f", months)) 个月")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
                Text("最近更新：\(latest.date.chineseDateTimeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("暂无健康数据")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 会话列表

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("充电记录")
                    .font(.headline)
                Spacer()
            }
            ForEach(viewModel.sessions.sorted { $0.startDate > $1.startDate }.prefix(5)) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.startDate.chineseDateTimeText)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(session.isActive ? "充电中" : "\(Int(session.duration / 60)) 分钟")
                            .font(.caption)
                            .foregroundStyle(session.isActive ? .green : .secondary)
                    }
                    if let speed = session.speedPercentPerHour {
                        Text("平均 \(Int(speed.rounded()))%/h")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// 健康详情页
struct HealthDetailView: View {
    @ObservedObject var viewModel: BatteryViewModel

    var body: some View {
        List {
            Section {
                if let latest = viewModel.latestHealth(records: viewModel.healthRecords) {
                    HStack {
                        Text("最大容量")
                        Spacer()
                        Text("\(String(format: "%.1f", latest.maximumCapacity))%")
                            .font(.headline)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("循环次数")
                        Spacer()
                        Text(latest.cycleCount.map { "\($0)" } ?? "--")
                    }
                    HStack {
                        Text("备注")
                        Spacer()
                        Text(latest.note ?? "--")
                    }
                } else {
                    Text("暂无健康数据")
                }
            } header: {
                Text("当前")
            }

            if !viewModel.healthRecords.isEmpty {
                Section {
                    ForEach(viewModel.healthRecords.sorted { $0.date > $1.date }) { r in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.date.chineseDateTimeText)
                                .font(.subheadline)
                            Text("\(String(format: "%.0f", r.maximumCapacity))% · \(r.cycleCount.map { "\($0) 次循环" } ?? "无循环记录")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.deleteHealth(r)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("历史")
                }
            }
        }
        .navigationTitle("电池健康")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddHealthView(viewModel: viewModel)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

/// 新增健康记录
struct AddHealthView: View {
    @ObservedObject var viewModel: BatteryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var capacity = ""
    @State private var cycles = ""
    @State private var note = ""

    var body: some View {
        Form {
            Section("最大容量（%）") {
                TextField("如 88", text: $capacity)
                    .keyboardType(.decimalPad)
            }
            Section("循环次数（可选）") {
                TextField("如 755", text: $cycles)
                    .keyboardType(.numberPad)
            }
            Section("备注（可选）") {
                TextField("备注", text: $note)
            }
            Section {
                Button {
                    save()
                } label: {
                    Text("保存")
                        .frame(maxWidth: .infinity)
                }
                .disabled(Double(capacity) == nil)
            }
        }
        .navigationTitle("新增健康记录")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        guard let cap = Double(capacity) else { return }
        viewModel.addHealth(capacity: cap,
                            cycles: Int(cycles),
                            note: note.isEmpty ? nil : note)
        dismiss()
    }
}
