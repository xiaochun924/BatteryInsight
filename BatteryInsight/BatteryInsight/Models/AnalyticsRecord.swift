import Foundation

/// 从 iOS 分析日志（Analytics-*.ips）解析出的一次电池健康快照。
///
/// 数据来源：系统「设置 → 隐私与安全性 → 分析与改进 → 分析数据」中的
/// `Analytics-YYYYMMDD-*.ips`，其中的 `batteryhealth` 段落。
///
/// 说明：以下字段全部是 iOS 日志中**实际存在**的原生值，未做推测计算。
struct AnalyticsRecord: Codable, Identifiable, Equatable {
    let id: UUID
    /// 日志采样时间
    let date: Date
    /// 系统健康度（%）—— 对应日志中的 MaximumCapacityPercent
    let systemHealthPercent: Double?
    /// 循环次数 —— CycleCount
    let cycleCount: Int?
    /// 当前实际容量（mAh）—— NominalChargeCapacity
    let nominalChargeCapacity: Int?
    /// 出厂/设计容量（mAh）—— DesignCapacity
    let designCapacity: Int?
    /// 电池电压（V）
    let voltage: Double?
    /// 电池温度（℃）
    let temperature: Double?
    /// 原始日志片段（便于回溯核对，最多保留 4000 字符）
    let rawSnippet: String

    init(id: UUID = UUID(),
         date: Date,
         systemHealthPercent: Double? = nil,
         cycleCount: Int? = nil,
         nominalChargeCapacity: Int? = nil,
         designCapacity: Int? = nil,
         voltage: Double? = nil,
         temperature: Double? = nil,
         rawSnippet: String = "") {
        self.id = id
        self.date = date
        self.systemHealthPercent = systemHealthPercent
        self.cycleCount = cycleCount
        self.nominalChargeCapacity = nominalChargeCapacity
        self.designCapacity = designCapacity
        self.voltage = voltage
        self.temperature = temperature
        self.rawSnippet = rawSnippet
    }

    var dateText: String {
        date.formatted(.dateTime.year().month().day().hour().minute())
    }

    /// 是否解析到了至少一个有意义的字段
    var hasAnyMetric: Bool {
        systemHealthPercent != nil || cycleCount != nil
            || nominalChargeCapacity != nil || designCapacity != nil
            || voltage != nil || temperature != nil
    }
}

/// 解析结果包装：成功记录 / 失败原因 / 统计
struct AnalyticsParseResult {
    var records: [AnalyticsRecord] = []
    var warnings: [String] = []
    /// 输入文本中被识别出的日志条目数
    var entriesFound: Int = 0

    var isEmpty: Bool { records.isEmpty }

    var summary: String {
        if records.isEmpty {
            return warnings.first ?? "未在文本中找到可识别的电池健康数据"
        }
        var parts = ["解析出 \(records.count) 条电池记录"]
        if entriesFound > records.count {
            parts.append("（共扫描 \(entriesFound) 条日志，其余无电池字段）")
        }
        if !warnings.isEmpty {
            parts.append("· \(warnings.count) 条提示")
        }
        return parts.joined()
    }
}
