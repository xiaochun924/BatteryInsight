import Foundation

/// 一个衍生指标的完整描述：值 + 单位 + 计算公式 + 数据依据。
/// 之所以把公式一并带出来，是因为这些指标**不是 iOS 官方定义**，
/// 不同 App 口径可能不同，展示来源才能判断可信度。
struct DerivedMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
    let icon: String
    /// 计算口径说明
    let formula: String
    /// 数据依据（用了哪些原始字段）
    let basis: String

    var valueText: String { unit.isEmpty ? value : "\(value) \(unit)" }
}

/// 由一个或多个 AnalyticsRecord 推导出的分析指标。
enum DerivedMetrics {

    // MARK: - 汇总入口

    /// 基于最新一条记录生成衍生指标；若有多条，部分指标用趋势计算。
    ///
    /// 设计原则：**只输出定义明确、可复现的指标**。
    /// 网上一些工具会给出「衰减稳定性」「电芯一致性」等名称，
    /// 但其口径依赖日志中更多未公开字段（AppleRawMaxCapacity / Qmax / WeightedRa 等），
    /// 仅凭 DesignCapacity 与 NominalChargeCapacity 无法唯一确定——
    /// 强行拟合只会得到看似合理却无依据的数字，因此这里不提供。
    static func make(from records: [AnalyticsRecord]) -> [DerivedMetric] {
        guard let latest = records.max(by: { $0.date < $1.date }) else { return [] }
        var out: [DerivedMetric] = []

        if let m = computedHealth(latest) { out.append(m) }
        if let m = capacityMargin(latest) { out.append(m) }
        if let m = chargePerCycle(latest) { out.append(m) }

        // 以下为跨记录趋势类指标
        if let m = healthTrend(records) { out.append(m) }
        if let m = drainPerCycle(records) { out.append(m) }
        if let m = estimatedFullCycles(records) { out.append(m) }

        return out
    }

    // MARK: - 计算健康度

    /// 计算健康度 = 当前实际容量 / 出厂容量 × 100%
    ///
    /// 这就是截图里 101.72% 的来源：4906 / 4823 ≈ 1.0172。
    /// 出现 >100% 是正常的——出厂容量是标称值，实际电芯容量存在正公差。
    /// 出厂容量优先取日志 DesignCapacity（旧格式），iOS 26 日志缺失时按机型查官方标称。
    private static func computedHealth(_ r: AnalyticsRecord) -> DerivedMetric? {
        guard let nominal = r.nominalChargeCapacity else { return nil }
        let design = r.designCapacity ?? DeviceBatterySpec.current?.factoryCapacity
        guard let design, design > 0 else { return nil }
        let pct = Double(nominal) / Double(design) * 100
        let basis = r.designCapacity != nil
            ? "实际 \(nominal) mAh ÷ 出厂 \(design) mAh"
            : "实际 \(nominal) mAh ÷ 机型出厂 \(design) mAh（官方标称）"
        return DerivedMetric(
            title: "计算健康度",
            value: String(format: "%.1f", pct),
            unit: "%",
            icon: "function",
            formula: "当前实际容量 ÷ 出厂容量 × 100%",
            basis: basis)
    }

    // MARK: - 容量余量

    /// 容量余量 = 当前实际容量 − 出厂容量（mAh）
    ///
    /// 含义：相对出厂标称还剩多少余量。
    /// **负数属正常**——出厂容量是标称值，实际电芯存在正公差，
    /// 新机常见实际容量高于标称值，此时余量为正。
    private static func capacityMargin(_ r: AnalyticsRecord) -> DerivedMetric? {
        guard let nominal = r.nominalChargeCapacity,
              let design = r.designCapacity else { return nil }
        let diff = nominal - design
        return DerivedMetric(
            title: "容量余量",
            value: diff >= 0 ? "+\(diff)" : "\(diff)",
            unit: "mAh",
            icon: "arrow.left.arrow.right.circle",
            formula: "当前实际容量 − 出厂容量",
            basis: "\(nominal) − \(design) = \(diff >= 0 ? "+" : "")\(diff) mAh")
    }

    // MARK: - 每次循环容量

    /// 每次循环对应容量 = 当前实际容量 ÷ 循环次数（mAh/次）
    ///
    /// 反映电芯的容量规模与使用强度的比值，非「衰减率」。
    private static func chargePerCycle(_ r: AnalyticsRecord) -> DerivedMetric? {
        guard let nominal = r.nominalChargeCapacity,
              let cycles = r.cycleCount, cycles > 0 else { return nil }
        let v = Double(nominal) / Double(cycles)
        return DerivedMetric(
            title: "单位循环容量",
            value: String(format: "%.2f", v),
            unit: "mAh/次",
            icon: "divide.circle",
            formula: "当前实际容量 ÷ 循环次数",
            basis: "\(nominal) mAh ÷ \(cycles) 次")
    }

    // MARK: - 健康度趋势

    /// 健康度趋势：首末记录的容量百分比之差，折算为 %/月。
    private static func healthTrend(_ records: [AnalyticsRecord]) -> DerivedMetric? {
        let valid = records.filter { $0.nominalChargeCapacity != nil && $0.designCapacity != nil }
            .sorted { $0.date < $1.date }
        guard valid.count >= 2,
              let first = valid.first, let last = valid.last,
              let fn = first.nominalChargeCapacity, let fd = first.designCapacity, fd > 0,
              let ln = last.nominalChargeCapacity, let ld = last.designCapacity, ld > 0
        else { return nil }

        let firstPct = Double(fn) / Double(fd) * 100
        let lastPct = Double(ln) / Double(ld) * 100
        let months = last.date.timeIntervalSince(first.date) / (30 * 24 * 3600)
        guard months > 0.02 else { return nil }

        let rate = (firstPct - lastPct) / months
        return DerivedMetric(
            title: "健康度变化",
            value: String(format: "%+.2f", -rate),
            unit: "%/月",
            icon: "chart.line.downtrend.xyaxis",
            formula: "(首条健康度 − 末条健康度) ÷ 间隔月数",
            basis: String(format: "%.2f%% → %.2f%%，间隔 %.1f 个月", firstPct, lastPct, months))
    }

    // MARK: - 每循环衰减

    /// 每循环衰减 = 容量损失 ÷ 循环次数增量
    private static func drainPerCycle(_ records: [AnalyticsRecord]) -> DerivedMetric? {
        let valid = records.filter { $0.cycleCount != nil && $0.nominalChargeCapacity != nil }
            .sorted { $0.date < $1.date }
        guard valid.count >= 2,
              let first = valid.first, let last = valid.last,
              let fc = first.cycleCount, let fn = first.nominalChargeCapacity,
              let lc = last.cycleCount, let ln = last.nominalChargeCapacity
        else { return nil }

        let cycles = lc - fc
        let loss = fn - ln
        guard cycles > 0, loss > 0 else { return nil }
        let perCycle = Double(loss) / Double(cycles)
        return DerivedMetric(
            title: "每循环衰减",
            value: String(format: "%.2f", perCycle),
            unit: "mAh/次",
            icon: "arrow.2.circlepath",
            formula: "容量损失 ÷ 循环增量",
            basis: "损失 \(loss) mAh ÷ \(cycles) 次循环")
    }

    // MARK: - 预估剩余循环

    /// 按当前每循环衰减速率，估算容量降至 80% 还可循环多少次。
    /// 需要至少两条含「循环次数 + 实际容量」的记录。
    private static func estimatedFullCycles(_ records: [AnalyticsRecord]) -> DerivedMetric? {
        let valid = records
            .filter { $0.cycleCount != nil && $0.nominalChargeCapacity != nil && $0.designCapacity != nil }
            .sorted { $0.date < $1.date }
        guard valid.count >= 2,
              let first = valid.first, let last = valid.last,
              let fc = first.cycleCount, let fn = first.nominalChargeCapacity, let fd = first.designCapacity, fd > 0,
              let lc = last.cycleCount, let ln = last.nominalChargeCapacity,
              lc > fc, fn > ln
        else { return nil }

        let perCycle = Double(fn - ln) / Double(lc - fc)
        guard perCycle > 0.0001 else { return nil }

        // 目标：容量降到出厂容量的 80%
        let target = Double(fd) * 0.8
        let current = Double(ln)
        guard current > target else { return nil }
        let remaining = Int((current - target) / perCycle)
        let total = lc + remaining

        return DerivedMetric(
            title: "预计可用至 80%",
            value: "\(remaining)",
            unit: "次循环",
            icon: "hourglass",
            formula: "(当前容量 − 出厂容量×80%) ÷ 每循环衰减",
            basis: "每循环衰减 \(String(format: "%.2f", perCycle)) mAh；预计总循环约 \(total) 次")
    }

    // MARK: - 原生字段展示

    /// 直接从日志读取、未经推算的原生字段。
    ///
    /// 每项都标出**实际取自哪个键**——键名前缀因机型 / 系统版本而异
    /// （`last_value_CycleCount`、`cycle_count`、`CycleCount`…），
    /// 写死一个推测值会让人无法核对数字来源。
    static func nativeMetrics(from record: AnalyticsRecord) -> [DerivedMetric] {
        var out: [DerivedMetric] = []
        if let h = record.systemHealthPercent {
            out.append(DerivedMetric(
                title: "系统健康度", value: String(format: "%.1f", h), unit: "%",
                icon: "checkmark.seal",
                formula: source("health", in: record, fallback: "MaximumCapacityPercent"),
                basis: "日志原生字段"))
        }
        if let c = record.cycleCount {
            out.append(DerivedMetric(
                title: "循环次数", value: "\(c)", unit: "次",
                icon: "arrow.2.circlepath",
                formula: source("cycle", in: record, fallback: "CycleCount"),
                basis: "日志原生字段"))
        }
        if let n = record.nominalChargeCapacity {
            out.append(DerivedMetric(
                title: "出厂容量（标称）", value: "\(n)", unit: "mAh",
                icon: "battery.100",
                formula: source("nominal", in: record, fallback: "NominalChargeCapacity"),
                basis: "日志原生字段"))
        }
        if let v = record.rawMaxCapacity {
            out.append(DerivedMetric(
                title: "实时容量", value: "\(v)", unit: "mAh",
                icon: "bolt.batteryblock",
                formula: source("rawMax", in: record, fallback: "AppleRawMaxCapacity"),
                basis: "日志原生字段"))
        }
        if let d = record.designCapacity {
            out.append(DerivedMetric(
                title: "额定容量（设计）", value: "\(d)", unit: "mAh",
                icon: "shippingbox",
                formula: source("design", in: record, fallback: "DesignCapacity"),
                basis: "日志原生字段"))
        }
        if let v = record.voltage {
            out.append(DerivedMetric(
                title: "电池电压", value: String(format: "%.3f", v), unit: "V",
                icon: "bolt",
                formula: source("voltage", in: record, fallback: "Voltage"),
                basis: "日志原生字段"))
        }
        if let t = record.temperature {
            out.append(DerivedMetric(
                title: "电池温度", value: String(format: "%.1f", t), unit: "℃",
                icon: "thermometer",
                formula: source("temperature", in: record, fallback: "Temperature"),
                basis: "日志原生字段"))
        }
        if let d = record.firstUseDate {
            out.append(DerivedMetric(
                title: "首次使用日期", value: d.chineseDateText, unit: "",
                icon: "calendar.badge.clock",
                formula: source("firstUse", in: record, fallback: "DOFU"),
                basis: "日志原生字段（DOFU，Date Of First Use）"))
        }
        if let changed = record.batterySerialChanged {
            out.append(DerivedMetric(
                title: "电池来源",
                value: changed ? "疑似非原装 / 已更换" : "原装",
                unit: "",
                icon: "checkmark.shield",
                formula: source("batterySerialChanged", in: record, fallback: "BatterySerialChanged"),
                basis: "日志原生字段（false=原装，true=序列变更）"))
        }
        if let power = DerivedMetrics.maxChargePower(from: record) {
            out.append(power)
        }
        return out
    }

    /// 最大充电功率 = 峰值充电电流 × 峰值电压（W）。
    /// 日志给出 mA 与 mV，换算成 A 与 V 后相乘，粗略反映充电功率上限。
    static func maxChargePower(from record: AnalyticsRecord) -> DerivedMetric? {
        guard let current = record.maxChargeCurrent,
              let voltage = record.maxPackVoltage else { return nil }
        let watts = current * voltage
        return DerivedMetric(
            title: "最大充电功率",
            value: String(format: "%.1f", watts),
            unit: "W",
            icon: "bolt.fill",
            formula: "峰值充电电流 × 峰值电压",
            basis: "\(String(format: "%.2f", current)) A × \(String(format: "%.2f", voltage)) V")
    }

    private static func source(_ field: String,
                               in record: AnalyticsRecord,
                               fallback: String) -> String {
        "iOS 直接写入（\(record.fieldSources[field] ?? fallback)）"
    }
}
