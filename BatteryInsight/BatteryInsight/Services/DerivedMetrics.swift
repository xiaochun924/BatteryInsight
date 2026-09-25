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
}
