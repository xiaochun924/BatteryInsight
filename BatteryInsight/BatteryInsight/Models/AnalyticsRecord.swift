import Foundation

/// 从 iOS 分析日志（Analytics-*.ips）解析出的一次电池健康快照。
///
/// 数据来源：系统「设置 → 隐私与安全性 → 分析与改进 → 分析数据」中的
/// `Analytics-YYYYMMDD-*.ips`，其中的 `batteryhealth` 段落。
///
/// 说明：以下字段全部是 iOS 日志中**实际存在**的原生值，未做推测计算。
struct AnalyticsRecord: Codable, Identifiable, Equatable, Sendable {
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
    /// `batteryhealth` 里其余未单独建模的数值字段，例如
    /// AppleRawMaxCapacity、AppleRawNominalCapacity、Qmax、WeightedRa、PresentDOD 等。
    ///
    /// 不同机型 / 系统版本写入的字段集合本就不一样，这里「系统写什么就存什么」，
    /// 既不臆造含义，也不因为没建模而丢数据。
    var extraFields: [String: Double]

    init(id: UUID = UUID(),
         date: Date,
         systemHealthPercent: Double? = nil,
         cycleCount: Int? = nil,
         nominalChargeCapacity: Int? = nil,
         designCapacity: Int? = nil,
         voltage: Double? = nil,
         temperature: Double? = nil,
         rawSnippet: String = "",
         extraFields: [String: Double] = [:]) {
        self.id = id
        self.date = date
        self.systemHealthPercent = systemHealthPercent
        self.cycleCount = cycleCount
        self.nominalChargeCapacity = nominalChargeCapacity
        self.designCapacity = designCapacity
        self.voltage = voltage
        self.temperature = temperature
        self.rawSnippet = rawSnippet
        self.extraFields = extraFields
    }

    // MARK: - Codable

    // 自定义解码只为兼容旧版本已落盘的数据（当时还没有 extraFields）
    private enum CodingKeys: String, CodingKey {
        case id, date, systemHealthPercent, cycleCount, nominalChargeCapacity,
             designCapacity, voltage, temperature, rawSnippet, extraFields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        systemHealthPercent = try? c.decode(Double.self, forKey: .systemHealthPercent)
        cycleCount = try? c.decode(Int.self, forKey: .cycleCount)
        nominalChargeCapacity = try? c.decode(Int.self, forKey: .nominalChargeCapacity)
        designCapacity = try? c.decode(Int.self, forKey: .designCapacity)
        voltage = try? c.decode(Double.self, forKey: .voltage)
        temperature = try? c.decode(Double.self, forKey: .temperature)
        rawSnippet = (try? c.decode(String.self, forKey: .rawSnippet)) ?? ""
        extraFields = (try? c.decode([String: Double].self, forKey: .extraFields)) ?? [:]
    }

    var dateText: String {
        date.formatted(.dateTime.year().month().day().hour().minute())
    }

    /// 是否解析到了至少一个有意义的字段
    var hasAnyMetric: Bool {
        systemHealthPercent != nil || cycleCount != nil
            || nominalChargeCapacity != nil || designCapacity != nil
            || voltage != nil || temperature != nil
            || !extraFields.isEmpty
    }

    /// 额外字段按名称排序，便于稳定展示
    var sortedExtraFields: [(key: String, value: Double)] {
        extraFields.map { (key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }
}

/// 解析结果包装：成功记录 / 失败原因 / 统计
struct AnalyticsParseResult: Sendable {
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
