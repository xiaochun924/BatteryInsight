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
    /// 当前实际容量（mAh）—— NominalChargeCapacity（竞品口径的「出厂容量」）
    let nominalChargeCapacity: Int?
    /// 出厂/设计容量（mAh）—— DesignCapacity（仅部分旧格式日志才有）
    let designCapacity: Int?
    /// 实时容量（mAh）—— AppleRawMaxCapacity
    let rawMaxCapacity: Int?
    /// 满充容量范围（mAh）—— MinimumFCC / MaximumFCC
    var minFCC: Int?
    var maxFCC: Int?
    /// Qmax（mAh）—— MinimumQmax / MaximumQmax / QmaxCell0
    var minQmax: Int?
    var maxQmax: Int?
    var qmaxCell0: Int?
    /// 电压范围（V）—— MinimumPackVoltage / MaximumPackVoltage（日志为 mV，已换算）
    var minPackVoltage: Double?
    var maxPackVoltage: Double?
    /// 电流峰值（A）—— MaximumChargeCurrent / MaximumDischargeCurrent（日志为 mA，已换算，放电为正数）
    var maxChargeCurrent: Double?
    var maxDischargeCurrent: Double?
    /// 温度范围（℃）—— MinimumTemperature / MaximumTemperature（日志为 0.1℃，已换算）
    var minTemperature: Double?
    var maxTemperature: Double?
    /// 每日 SOC —— DailyMinSoc / DailyMaxSoc（%）
    var dailyMinSoc: Int?
    var dailyMaxSoc: Int?
    /// 累计运行时间（小时）—— TotalOperatingTime（日志 0.1h，已换算）
    var totalOperatingHours: Double?
    /// 当天未插电总时长（秒）—— UnpluggedDurationEnergyViewNew.daily_total_Duration。
    /// 即「文件抓取到的续航」：当天拔掉电源的累计时长，转成「X时Y分」直接展示。
    var unpluggedDurationSeconds: Double?
    /// 记录更新时间 —— UpdateTime（Unix 秒）
    var lastUpdateTime: Date?
    /// 首次使用日期 —— DOFU（Date Of First Use，Unix 秒）。
    /// 对 iPhone 15 及更新机型，系统在日志里写入电池首次启用时间；
    /// 旧机型日志无此键时为空。
    var firstUseDate: Date?
    /// 电池序列是否变更过 —— BatterySerialChanged（true 表示检测到非原装 / 更换）。
    /// 判断「电池来源」是否原装的依据；日志为 null 或 false 时视为原装。
    var batterySerialChanged: Bool?
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
    /// 每个字段**实际取自日志里的哪个键**（如 `last_value_CycleCount`）。
    ///
    /// 键名前缀因机型 / 系统版本而异，记下真实键名才能核对"数字到底从哪来的"，
    /// 而不是让 UI 永远显示一个写死的推测值。
    var fieldSources: [String: String]

    init(id: UUID = UUID(),
         date: Date,
         systemHealthPercent: Double? = nil,
         cycleCount: Int? = nil,
         nominalChargeCapacity: Int? = nil,
         designCapacity: Int? = nil,
         rawMaxCapacity: Int? = nil,
         minFCC: Int? = nil,
         maxFCC: Int? = nil,
         minQmax: Int? = nil,
         maxQmax: Int? = nil,
         qmaxCell0: Int? = nil,
         minPackVoltage: Double? = nil,
         maxPackVoltage: Double? = nil,
         maxChargeCurrent: Double? = nil,
         maxDischargeCurrent: Double? = nil,
         minTemperature: Double? = nil,
         maxTemperature: Double? = nil,
         dailyMinSoc: Int? = nil,
         dailyMaxSoc: Int? = nil,
         totalOperatingHours: Double? = nil,
         unpluggedDurationSeconds: Double? = nil,
         lastUpdateTime: Date? = nil,
         firstUseDate: Date? = nil,
         batterySerialChanged: Bool? = nil,
         voltage: Double? = nil,
         temperature: Double? = nil,
         rawSnippet: String = "",
         extraFields: [String: Double] = [:],
         fieldSources: [String: String] = [:]) {
        self.id = id
        self.date = date
        self.systemHealthPercent = systemHealthPercent
        self.cycleCount = cycleCount
        self.nominalChargeCapacity = nominalChargeCapacity
        self.designCapacity = designCapacity
        self.rawMaxCapacity = rawMaxCapacity
        self.minFCC = minFCC
        self.maxFCC = maxFCC
        self.minQmax = minQmax
        self.maxQmax = maxQmax
        self.qmaxCell0 = qmaxCell0
        self.minPackVoltage = minPackVoltage
        self.maxPackVoltage = maxPackVoltage
        self.maxChargeCurrent = maxChargeCurrent
        self.maxDischargeCurrent = maxDischargeCurrent
        self.minTemperature = minTemperature
        self.maxTemperature = maxTemperature
        self.dailyMinSoc = dailyMinSoc
        self.dailyMaxSoc = dailyMaxSoc
        self.totalOperatingHours = totalOperatingHours
        self.unpluggedDurationSeconds = unpluggedDurationSeconds
        self.lastUpdateTime = lastUpdateTime
        self.firstUseDate = firstUseDate
        self.batterySerialChanged = batterySerialChanged
        self.voltage = voltage
        self.temperature = temperature
        self.rawSnippet = rawSnippet
        self.extraFields = extraFields
        self.fieldSources = fieldSources
    }

    // MARK: - Codable

    // 自定义解码只为兼容旧版本已落盘的数据（当时还没有 extraFields / fieldSources）
    private enum CodingKeys: String, CodingKey {
        case id, date, systemHealthPercent, cycleCount, nominalChargeCapacity,
             designCapacity, rawMaxCapacity, minFCC, maxFCC, minQmax, maxQmax, qmaxCell0,
             minPackVoltage, maxPackVoltage, maxChargeCurrent, maxDischargeCurrent,
             minTemperature, maxTemperature, dailyMinSoc, dailyMaxSoc,
             totalOperatingHours, unpluggedDurationSeconds, lastUpdateTime,
             voltage, temperature, rawSnippet, extraFields, fieldSources, firstUseDate,
             batterySerialChanged
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        date = (try? c.decode(Date.self, forKey: .date)) ?? Date()
        systemHealthPercent = try? c.decode(Double.self, forKey: .systemHealthPercent)
        cycleCount = try? c.decode(Int.self, forKey: .cycleCount)
        nominalChargeCapacity = try? c.decode(Int.self, forKey: .nominalChargeCapacity)
        designCapacity = try? c.decode(Int.self, forKey: .designCapacity)
        rawMaxCapacity = try? c.decode(Int.self, forKey: .rawMaxCapacity)
        minFCC = try? c.decode(Int.self, forKey: .minFCC)
        maxFCC = try? c.decode(Int.self, forKey: .maxFCC)
        minQmax = try? c.decode(Int.self, forKey: .minQmax)
        maxQmax = try? c.decode(Int.self, forKey: .maxQmax)
        qmaxCell0 = try? c.decode(Int.self, forKey: .qmaxCell0)
        minPackVoltage = try? c.decode(Double.self, forKey: .minPackVoltage)
        maxPackVoltage = try? c.decode(Double.self, forKey: .maxPackVoltage)
        maxChargeCurrent = try? c.decode(Double.self, forKey: .maxChargeCurrent)
        maxDischargeCurrent = try? c.decode(Double.self, forKey: .maxDischargeCurrent)
        minTemperature = try? c.decode(Double.self, forKey: .minTemperature)
        maxTemperature = try? c.decode(Double.self, forKey: .maxTemperature)
        dailyMinSoc = try? c.decode(Int.self, forKey: .dailyMinSoc)
        dailyMaxSoc = try? c.decode(Int.self, forKey: .dailyMaxSoc)
        totalOperatingHours = try? c.decode(Double.self, forKey: .totalOperatingHours)
        unpluggedDurationSeconds = try? c.decode(Double.self, forKey: .unpluggedDurationSeconds)
        lastUpdateTime = try? c.decode(Date.self, forKey: .lastUpdateTime)
        firstUseDate = try? c.decode(Date.self, forKey: .firstUseDate)
        batterySerialChanged = try? c.decode(Bool.self, forKey: .batterySerialChanged)
        voltage = try? c.decode(Double.self, forKey: .voltage)
        temperature = try? c.decode(Double.self, forKey: .temperature)
        rawSnippet = (try? c.decode(String.self, forKey: .rawSnippet)) ?? ""
        extraFields = (try? c.decode([String: Double].self, forKey: .extraFields)) ?? [:]
        fieldSources = (try? c.decode([String: String].self, forKey: .fieldSources)) ?? [:]
    }

    /// 是否含核心电池指标（健康度 / 循环 / 容量）。
    ///
    /// 只有电压或温度不算——那说明抓到的是日志里别的段落（温控、功耗），
    /// 当成电池记录入库会污染趋势图。
    var hasCoreMetric: Bool {
        systemHealthPercent != nil || cycleCount != nil
            || nominalChargeCapacity != nil || designCapacity != nil
    }

    /// 中文日期（跟设备语言无关）：「2026年9月23日 08:00」
    var dateText: String { date.chineseDateTimeText }

    /// 是否解析到了至少一个有意义的字段
    var hasAnyMetric: Bool {
        systemHealthPercent != nil || cycleCount != nil
            || nominalChargeCapacity != nil || designCapacity != nil
            || voltage != nil || temperature != nil
            || unpluggedDurationSeconds != nil
            || !extraFields.isEmpty
    }

    /// 把当天未插电时长（秒）补进记录（独立段解析后合并到同一天主记录用）
    func withUnpluggedDuration(_ seconds: Double) -> AnalyticsRecord {
        var r = self
        r.unpluggedDurationSeconds = seconds
        return r
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
