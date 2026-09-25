import Foundation

/// iOS 分析日志（Analytics-*.ips / log-aggregated-*.ips）电池数据解析器。
///
/// ## 真实结构
///
/// `Analytics-*.ips` 是**一行一个 JSON 对象**。第一行是表头（含 `timestamp`、
/// `os_version`），其余行的 `message` 对象里带当天聚合的电池统计，键名统一带
/// `last_value_` 前缀：
///
/// ```
/// {"timestamp":"2026-09-24 08:00:08.00 +0800","os_version":"iPhone OS 26.0 (23A340)",…}
/// {"message":{"last_value_CycleCount":755,"last_value_MaximumCapacityPercent":88,
///             "last_value_NominalChargeCapacity":4321,
///             "last_value_AppleRawMaxCapacity":4400,"last_value_DailyMaxSoc":100,…}}
/// ```
///
/// 旧一些的 `log-aggregated-*.ips` 是 plist 风格，键名形如
/// `com.apple.power.battery.cycle_count`。
///
/// ⚠️ 曾经踩过的坑：早期版本假设数据装在 `batteryhealth` 对象里、键名是
/// `CycleCount` / `MaximumCapacityPercent`。实际日志两者都不符，于是结构化
/// 解析全部落空，退回正则扫描后抓到的是**无关数字**——表现就是"循环次数、
/// 健康度都不对"。
///
/// 因此这里**不穷举键名**：把键名规整成「只留字母数字的小写串」后按后缀
/// 匹配语义，`last_value_CycleCount`、`cycle_count`、`CycleCount`、
/// `BatteryCycleCount` 都能落到同一条规则上。
enum AnalyticsLogParser {

    // MARK: - 字段语义

    enum Field {
        case health, cycle, nominal, design, voltage, temperature, rawMax
        // iOS 26 BatteryConfigValueHistogram 键集（已与真实日志逐值核对）
        case minFCC, maxFCC
        case minQmax, maxQmax, qmaxCell0
        case minPackV, maxPackV
        case chargeCurrent, dischargeCurrent
        case minTemp, maxTemp, avgTemp
        case dailyMinSoc, dailyMaxSoc
        case operatingTime, updateTime
        case firstUse, batterySerialChanged
    }

    private struct Pick {
        let key: String
        let value: Double
    }

    /// 规整键名：小写 + 只保留字母数字。
    /// `last_value_CycleCount` → `lastvaluecyclecount`
    private static func normalized(_ key: String) -> String {
        var out = ""
        for ch in key.lowercased() where ch.isLetter || ch.isNumber { out.append(ch) }
        return out
    }

    /// 候选键名后缀（按优先级）：命中第一个「后缀匹配 + 数值合理」的为止。
    /// 之所以是后缀而不是全等，就是要覆盖各种前缀写法。
    ///
    /// ⚠️ design 列表里**绝不能加 maximumfcc**——iOS 26 日志没有 DesignCapacity 键，
    /// 加了兜底就会抓到 last_value_MaximumFCC（当天满充容量上限，比如 4976），
    /// 被当成出厂容量，健康度计算全错（这正是历史上"出厂容量 4976"的来源）。
    private static let healthKeys  = ["maximumcapacitypercent", "capacitypercent",
                                      "maximumcapacitypct", "systemhealthpercent"]
    private static let cycleKeys   = ["cyclecount", "batterycyclecount",
                                      "cyclecounttotal", "totalcyclecount"]
    private static let nominalKeys = ["nominalchargecapacity", "nominalcapacity"]
    private static let designKeys  = ["designcapacity", "designchargecapacity"]
    private static let rawMaxKeys  = ["rawmaxcapacity"]
    private static let voltageKeys = ["packvoltage"]
    private static let tempKeys    = ["averagetemperature"]

    private static func candidates(for field: Field) -> [String] {
        switch field {
        case .health: return healthKeys
        case .cycle: return cycleKeys
        case .nominal: return nominalKeys
        case .design: return designKeys
        case .rawMax: return rawMaxKeys
        case .voltage: return voltageKeys
        case .temperature: return tempKeys
        default: return []
        }
    }

    /// 已验证的精确键（归一化后按后缀匹配，键名来自真实日志样本，不做臆测）：
    /// 温度原始值 0.1℃、电压 mV、电流 mA、运行时间 0.1h、更新时间 Unix 秒。
    private static let exactKeys: [Field: [String]] = [
        .minFCC: ["minimumfcc"],
        .maxFCC: ["maximumfcc"],
        .minQmax: ["minimumqmax"],
        .maxQmax: ["maximumqmax"],
        .qmaxCell0: ["qmaxcell0"],
        .minPackV: ["minimumpackvoltage"],
        .maxPackV: ["maximumpackvoltage"],
        .chargeCurrent: ["maximumchargecurrent"],
        .dischargeCurrent: ["maximumdischargecurrent"],
        .minTemp: ["minimumtemperature"],
        .maxTemp: ["maximumtemperature"],
        .dailyMinSoc: ["dailyminsoc", "minimumchargesoc"],
        .dailyMaxSoc: ["dailymaxsoc", "maximumchargesoc"],
        .operatingTime: ["totaloperatingtime"],
        .updateTime: ["updatetime"],
        .firstUse: ["dofu"],
        .batterySerialChanged: ["batteryserialchanged"],
    ]

    /// 判断某个键对应哪个字段；不属于电池字段则返回 nil
    /// （UI 也会用它判断某键是否已被单独展示）
    static func field(of key: String) -> Field? {
        let n = normalized(key)
        guard !n.isEmpty else { return nil }
        // 精确键优先（避免 minimumpackvoltage 被 voltage 抢走之类）
        for (f, keys) in exactKeys where keys.contains(where: { n.hasSuffix($0) }) {
            return f
        }
        // 顺序有讲究：nominalchargecapacity 不能被 designcapacity 抢走，
        // maximumcapacitypercent 也不能因为含 capacity 被当成容量
        for f in [Field.health, .nominal, .design, .cycle, .rawMax, .voltage, .temperature] {
            if candidates(for: f).contains(where: { n.hasSuffix($0) }) { return f }
        }
        return nil
    }

    private static func isCore(_ field: Field) -> Bool {
        switch field {
        case .health, .cycle, .nominal, .design: return true
        default: return false
        }
    }

    /// 数值合理性。抓错键会给出一个看起来合理的错数字，所以按物理量级再兜一层。
    /// 单位均为日志原始单位（温度 0.1℃、电压 mV、电流 mA、时间 0.1h）。
    private static func plausible(_ field: Field, _ v: Double) -> Bool {
        switch field {
        case .health, .dailyMinSoc, .dailyMaxSoc: return v >= 1 && v <= 150
        case .cycle: return v >= 0 && v <= 10000
        case .nominal, .design, .rawMax, .minFCC, .maxFCC,
             .minQmax, .maxQmax, .qmaxCell0: return v >= 100 && v <= 20000
        case .minPackV, .maxPackV, .voltage: return v >= 2000 && v <= 6000
        case .chargeCurrent, .dischargeCurrent: return abs(v) >= 10 && abs(v) <= 20000
        case .minTemp, .maxTemp, .avgTemp: return v >= -500 && v <= 1500
        case .temperature: return v >= -50 && v <= 150
        case .operatingTime: return v >= 0 && v <= 100_000_000
        case .updateTime: return v >= 1_000_000_000 && v <= 5_000_000_000
        case .firstUse: return v >= 1_000_000_000 && v <= 5_000_000_000
        case .batterySerialChanged: return v == 0 || v == 1
        }
    }

    // MARK: - 对外入口

    static func parse(_ text: String) -> AnalyticsParseResult {
        var result = AnalyticsParseResult()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.warnings.append("输入为空")
            return result
        }

        let stamps = timestampMatches(in: text)
        // Daily 聚合日志：文件 metadata 行的 startTimestamp 才是数据对应日期，
        // 表头 timestamp 是生成时刻（次日早上），直接用会把记录日期推后一天
        let fileDate = fileStartDate(from: text)
        let entries = topLevelJSONObjects(in: text).filter { looksLikeBattery($0.raw) }
        result.entriesFound = entries.count

        var records: [AnalyticsRecord] = []
        var missingDate = false

        for entry in entries {
            guard let object = dictionary(from: entry.raw),
                  let source = batterySource(in: object) else { continue }
            // 日期优先级：电池行自带日期 > 文件聚合起始日（startTimestamp）
            // > 行之前最近的时间戳（表头生成时刻）
            let date = extractDate(from: object)
                ?? fileDate
                ?? nearestDate(before: entry.start, in: stamps)
            guard let date = date else { missingDate = true; continue }
            if let r = record(from: source, date: date, raw: entry.raw) {
                records.append(r)
            }
        }

        // 兜底：JSON 结构对不上时（截断 / 只复制了片段 / plist 格式），
        // 直接在全文里扫「键 → 数值」
        if records.isEmpty {
            let fallback = scanFallback(text, stamps: stamps, fileDate: fileDate)
            records = fallback
            if !records.isEmpty {
                result.warnings.append("未匹配到标准 JSON 结构，已用通用键值扫描兜底，请与原始日志核对")
            }
        }

        // 同一天只留字段最完整的一条：一天日志里电池统计可能出现多次，
        // 全部入库只会把趋势图挤成一堆重复点
        var byDay: [Date: AnalyticsRecord] = [:]
        for r in records {
            let day = Calendar.current.startOfDay(for: r.date)
            if let old = byDay[day] {
                if completeness(r) > completeness(old) { byDay[day] = r }
            } else {
                byDay[day] = r
            }
        }
        result.records = byDay.values.sorted { $0.date < $1.date }

        if result.records.isEmpty {
            result.warnings.append(
                "未识别到电池数据。请确认选中的是「分析数据」里的 "
                + "Analytics-*.ips 或 log-aggregated-*.ips。")
            let keys = collectCandidateKeys(from: text)
            if !keys.isEmpty {
                result.warnings.append("日志中发现这些疑似电池相关的键：\(keys)。")
            }
        } else if missingDate {
            result.warnings.append("部分记录未找到时间戳，已跳过")
        }

        return result
    }

    // MARK: - 顶层 JSON 对象切分

    /// 廉价预筛：28 MB 日志里有几万行 JSON，只有少数几行含电池数据。
    /// 先做子串判断，避免对每个对象都跑一次 JSONSerialization。
    private static func looksLikeBattery(_ raw: String) -> Bool {
        let probes = ["yclecount", "ycle_count", "apacitypercent", "apacity_percent",
                      "ominalchargecapacity", "ominal_charge_capacity",
                      "esigncapacity", "esign_capacity"]
        for p in probes where raw.range(of: p, options: .caseInsensitive) != nil {
            return true
        }
        return false
    }

    private struct Entry {
        let raw: String
        let start: Int
    }

    /// 按花括号配平切出顶层 JSON 对象，正确处理字符串内的 `{` `}` 与转义。
    ///
    /// 走 UTF-8 字节而不是 `String.indices`：几十 MB 的日志按 Character 遍历
    /// 要十几秒（界面就是这么"黑屏"的），字节扫描快一个数量级。
    private static func topLevelJSONObjects(in text: String) -> [Entry] {
        let bytes = Array(text.utf8)
        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")
        let open = UInt8(ascii: "{")
        let close = UInt8(ascii: "}")

        var out: [Entry] = []
        var depth = 0
        var start: Int?
        var inString = false
        var escaped = false

        for i in 0..<bytes.count {
            let c = bytes[i]
            if inString {
                if escaped {
                    escaped = false
                } else if c == backslash {
                    escaped = true
                } else if c == quote {
                    inString = false
                }
                continue
            }
            if c == quote {
                inString = true
            } else if c == open {
                if depth == 0 { start = i }
                depth += 1
            } else if c == close {
                depth -= 1
                if depth <= 0, let s = start {
                    if i - s + 1 >= 2, let piece = String(bytes: bytes[s...i], encoding: .utf8) {
                        out.append(Entry(raw: piece, start: s))
                    }
                    start = nil
                    depth = 0
                }
            }
        }
        return out
    }

    private static func dictionary(from raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any] else { return nil }
        return dict
    }

    // MARK: - 定位电池数据

    /// 找出承载电池字段的那个字典。
    ///
    /// 优先 `message`（CoreAnalytics 格式），再 `batteryhealth`（旧格式），
    /// 最后才考虑对象本身或下钻一层。
    private static func batterySource(in object: [String: Any]) -> [String: Any]? {
        // 跳过蓝牙配件（耳机 / 充电盒等）电池段——它们不是 iPhone 电池，
        // 里面的 `cycle_count`（如 734/765/767）会污染 iPhone 的循环次数，
        // 造成同一天出现几百次的错误循环数。
        if let name = object["name"] as? String,
           name.hasPrefix("BT_Accessory_") { return nil }
        if let message = dictValue("message", in: object), hasCoreField(message) { return message }
        if let section = findBatterySection(in: object) { return section }
        if hasCoreField(object) { return object }
        return deepFind(in: object, depth: 0)
    }

    private static func dictValue(_ key: String, in dict: [String: Any]) -> [String: Any]? {
        if let v = dict[key] as? [String: Any] { return v }
        for (k, v) in dict where k.caseInsensitiveCompare(key) == .orderedSame {
            if let d = v as? [String: Any] { return d }
        }
        return nil
    }

    /// 只有「健康度 / 循环 / 容量」能证明这是电池数据。
    /// Voltage / Temperature 太通用——日志里温控、功耗段落也有，会造成误判。
    private static func hasCoreField(_ dict: [String: Any]) -> Bool {
        pick(.health, in: dict) != nil || pick(.cycle, in: dict) != nil
            || pick(.nominal, in: dict) != nil || pick(.design, in: dict) != nil
    }

    private static let batterySectionNames: Set<String> = [
        "batteryhealth", "batteryhealthdata", "batterydata"
    ]

    private static func findBatterySection(in dict: [String: Any], depth: Int = 0) -> [String: Any]? {
        for (key, value) in dict where batterySectionNames.contains(normalized(key)) {
            if let nested = value as? [String: Any] { return nested }
        }
        guard depth < 2 else { return nil }
        for (_, value) in dict {
            if let nested = value as? [String: Any],
               let found = findBatterySection(in: nested, depth: depth + 1) { return found }
        }
        return nil
    }

    private static func deepFind(in dict: [String: Any], depth: Int) -> [String: Any]? {
        guard depth < 3 else { return nil }
        for (_, value) in dict {
            guard let nested = value as? [String: Any] else { continue }
            if hasCoreField(nested) { return nested }
            if let found = deepFind(in: nested, depth: depth + 1) { return found }
        }
        return nil
    }

    // MARK: - 取值

    /// 按候选优先级取第一个「后缀匹配 + 数值合理」的键值
    private static func pick(_ field: Field, in dict: [String: Any]) -> Pick? {
        for candidate in candidates(for: field) {
            for (key, value) in dict {
                guard normalized(key).hasSuffix(candidate),
                      let v = numeric(value),
                      plausible(field, v) else { continue }
                return Pick(key: key, value: v)
            }
        }
        return nil
    }

    /// 精确键取值（用于 MinimumFCC / PackVoltage 等已验证字段）
    private static func pickExact(_ field: Field, in dict: [String: Any]) -> Pick? {
        guard let keys = exactKeys[field] else { return nil }
        for candidate in keys {
            for (key, value) in dict {
                guard normalized(key).hasSuffix(candidate),
                      let v = numeric(value),
                      plausible(field, v) else { continue }
                return Pick(key: key, value: v)
            }
        }
        return nil
    }

    /// JSON 数值可能是 NSNumber，也可能是带引号的字符串
    private static func numeric(_ any: Any?) -> Double? {
        guard let any = any else { return nil }
        if any is Bool { return nil }                 // 别把布尔当 1/0
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String {
            return Double(s.trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// 提取 JSON 布尔值（如 `"last_value_BatterySerialChanged": false`）。
    /// `numeric()` 会拒绝 Bool，所以布尔字段必须单独走这条路径。
    private static func boolExact(_ field: Field, in dict: [String: Any]) -> Bool? {
        guard let keys = exactKeys[field] else { return nil }
        for candidate in keys {
            for (key, value) in dict where normalized(key).hasSuffix(candidate) {
                if let b = value as? Bool { return b }
                if let n = numeric(value) { return n != 0 }
            }
        }
        return nil
    }

    // MARK: - 组装记录

    private static func record(from source: [String: Any],
                               date: Date,
                               raw: String) -> AnalyticsRecord? {
        let health = pick(.health, in: source)
        let cycle = pick(.cycle, in: source)
        let nominal = pick(.nominal, in: source)
        let design = pick(.design, in: source)

        func exact(_ f: Field) -> Double? { pickExact(f, in: source)?.value }

        // 记下每个字段实际取自哪个键，UI 上如实展示，便于核对
        var sources: [String: String] = [:]
        if let p = health { sources["health"] = p.key }
        if let p = cycle { sources["cycle"] = p.key }
        if let p = nominal { sources["nominal"] = p.key }
        if let p = design { sources["design"] = p.key }
        if let p = pickExact(.rawMax, in: source) { sources["rawMax"] = p.key }

        // 单位换算：电压 mV → V；电流 mA → A（放电为负值，取绝对值）；
        // 温度 0.1℃ → ℃；运行时间 0.1h → h；更新时间 Unix 秒 → Date
        let record = AnalyticsRecord(
            date: date,
            systemHealthPercent: health?.value,
            cycleCount: cycle.map { Int($0.value.rounded()) },
            nominalChargeCapacity: nominal.map { Int($0.value.rounded()) },
            designCapacity: design.map { Int($0.value.rounded()) },
            rawMaxCapacity: pickExact(.rawMax, in: source).map { Int($0.value.rounded()) },
            minFCC: exact(.minFCC).map { Int($0.rounded()) },
            maxFCC: exact(.maxFCC).map { Int($0.rounded()) },
            minQmax: exact(.minQmax).map { Int($0.rounded()) },
            maxQmax: exact(.maxQmax).map { Int($0.rounded()) },
            qmaxCell0: exact(.qmaxCell0).map { Int($0.rounded()) },
            minPackVoltage: exact(.minPackV).map { $0 / 1000 },
            maxPackVoltage: exact(.maxPackV).map { $0 / 1000 },
            maxChargeCurrent: exact(.chargeCurrent).map { abs($0) / 1000 },
            maxDischargeCurrent: exact(.dischargeCurrent).map { abs($0) / 1000 },
            minTemperature: exact(.minTemp).map { $0 / 10 },
            maxTemperature: exact(.maxTemp).map { $0 / 10 },
            dailyMinSoc: exact(.dailyMinSoc).map { Int($0.rounded()) },
            dailyMaxSoc: exact(.dailyMaxSoc).map { Int($0.rounded()) },
            totalOperatingHours: exact(.operatingTime).map { $0 / 10 },
            lastUpdateTime: exact(.updateTime).map { Date(timeIntervalSince1970: $0) },
            firstUseDate: exact(.firstUse).map { Date(timeIntervalSince1970: $0) },
            batterySerialChanged: boolExact(.batterySerialChanged, in: source),
            voltage: pick(.voltage, in: source).map { $0.value / 1000 },
            temperature: pick(.temperature, in: source).map { $0.value },
            rawSnippet: String(raw.prefix(4000)),
            extraFields: extraFields(in: source),
            fieldSources: sources)

        return record.hasCoreMetric ? record : nil
    }

    /// 同一天多条记录时，字段更全的那条优先
    private static func completeness(_ r: AnalyticsRecord) -> Int {
        var score = 0
        if r.systemHealthPercent != nil { score += 4 }
        if r.cycleCount != nil { score += 4 }
        if r.nominalChargeCapacity != nil { score += 3 }
        if r.rawMaxCapacity != nil { score += 2 }
        if r.maxFCC != nil { score += 2 }
        if r.designCapacity != nil { score += 1 }
        if r.maxPackVoltage != nil { score += 1 }
        if r.maxTemperature != nil { score += 1 }
        if r.firstUseDate != nil { score += 1 }
        if r.batterySerialChanged != nil { score += 1 }
        return score + min(r.extraFields.count, 10)
    }

    /// `message` 里未被单独建模的数值字段（AppleRawMaxCapacity、DailyMaxSoc…）。
    /// 系统写什么就存什么，但不做解读。
    private static func extraFields(in source: [String: Any], limit: Int = 30) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, value) in source {
            guard let v = numeric(value), !isModeled(key) else { continue }
            out[key] = v
        }
        guard out.count > limit else { return out }
        let sorted = out.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
        return Dictionary(uniqueKeysWithValues: sorted.prefix(limit).map { ($0.key, $0.value) })
    }

    private static func isModeled(_ key: String) -> Bool {
        classifies(key)
    }

    /// 该键是否已被解析器归类（UI 据此避免重复展示）
    static func classifies(_ key: String) -> Bool {
        field(of: key) != nil
    }

    // MARK: - 时间戳

    private static func extractDate(from object: [String: Any]) -> Date? {
        for key in ["timestamp", "created_at", "CreationDate", "date"] {
            if let s = stringValue(of: key, in: object), let d = parseDateString(s) { return d }
        }
        return nil
    }

    private static func stringValue(of key: String, in dict: [String: Any]) -> String? {
        if let s = dict[key] as? String { return s }
        for (k, v) in dict where k.caseInsensitiveCompare(key) == .orderedSame {
            if let s = v as? String { return s }
        }
        return nil
    }

    // MARK: - 兜底：通用键值扫描

    private struct Pair {
        let field: Field
        let key: String
        let value: Double
        let location: Int
        let length: Int
    }

    /// 不依赖 JSON 结构，直接在全文里扫「键 → 数值」。
    /// 覆盖 JSON 的 `"key": 123` 与 plist 的 `<key>k</key><integer>123</integer>`。
    private static func scanFallback(_ text: String, stamps: [Stamp], fileDate: Date?) -> [AnalyticsRecord] {
        var pairs: [Pair] = []
        pairs.append(contentsOf: scanPairs(
            in: text,
            pattern: "\"([A-Za-z0-9_.\\-]{3,80})\"\\s*:\\s*\"?(-?[0-9]+(?:\\.[0-9]+)?)\"?",
            keyIndex: 1, valueIndex: 2))
        pairs.append(contentsOf: scanPairs(
            in: text,
            pattern: "<key>([^<]{3,80})</key>\\s*<(?:integer|real)>(-?[0-9]+(?:\\.[0-9]+)?)</",
            keyIndex: 1, valueIndex: 2))

        guard !pairs.isEmpty else { return [] }

        var out: [AnalyticsRecord] = []
        for group in cluster(pairs) {
            guard let start = group.map(\.location).min(),
                  group.contains(where: { isCore($0.field) }),
                  let date = fileDate ?? nearestDate(before: start, in: stamps) ?? firstStamp(in: stamps)
            else { continue }

            var sources: [String: String] = [:]
            var extras: [String: Double] = [:]
            var health: Double?, cycle: Double?, nominal: Double?, design: Double?
            var voltage: Double?, temperature: Double?

            for pair in group {
                switch pair.field {
                case .health:
                    if health == nil { health = pair.value; sources["health"] = pair.key }
                case .cycle:
                    if cycle == nil { cycle = pair.value; sources["cycle"] = pair.key }
                case .nominal:
                    if nominal == nil { nominal = pair.value; sources["nominal"] = pair.key }
                case .design:
                    if design == nil { design = pair.value; sources["design"] = pair.key }
                case .voltage:
                    if voltage == nil { voltage = pair.value; sources["voltage"] = pair.key }
                case .temperature:
                    if temperature == nil { temperature = pair.value; sources["temperature"] = pair.key }
                default:
                    extras[pair.key] = pair.value
                }
            }

            let record = AnalyticsRecord(
                date: date,
                systemHealthPercent: health,
                cycleCount: cycle.map { Int($0.rounded()) },
                nominalChargeCapacity: nominal.map { Int($0.rounded()) },
                designCapacity: design.map { Int($0.rounded()) },
                voltage: voltage.map { $0 / 1000 },
                temperature: temperature,
                rawSnippet: snippet(around: group, in: text),
                extraFields: extras,
                fieldSources: sources)

            if record.hasCoreMetric { out.append(record) }
        }
        return out
    }

    private static func scanPairs(in text: String,
                                  pattern: String,
                                  keyIndex: Int,
                                  valueIndex: Int) -> [Pair] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [] }
        let ns = text as NSString
        var out: [Pair] = []
        regex.enumerateMatches(in: text, options: [],
                               range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges > max(keyIndex, valueIndex),
                  let kr = Range(match.range(at: keyIndex), in: text),
                  let vr = Range(match.range(at: valueIndex), in: text) else { return }
            let key = String(text[kr])
            guard let value = Double(text[vr]),
                  let field = field(of: key),
                  plausible(field, value) else { return }
            out.append(Pair(field: field, key: key, value: value,
                            location: match.range.location, length: match.range.length))
        }
        return out
    }

    /// 切分信号：间隔过远，或同一键重复出现（一段电池数据里同键不会出现两次）
    private static func cluster(_ pairs: [Pair], maxGap: Int = 2000) -> [[Pair]] {
        guard !pairs.isEmpty else { return [] }
        let sorted = pairs.sorted { $0.location < $1.location }
        var clusters: [[Pair]] = []
        var current: [Pair] = [sorted[0]]
        var last = sorted[0].location

        for p in sorted.dropFirst() {
            let tooFar = p.location - last > maxGap
            let repeated = current.contains { $0.key == p.key }
            if tooFar || repeated {
                clusters.append(current)
                current = []
            }
            current.append(p)
            last = p.location
        }
        clusters.append(current)
        return clusters
    }

    private static func snippet(around group: [Pair],
                                in text: String,
                                padding: Int = 600,
                                limit: Int = 4000) -> String {
        guard let start = group.map(\.location).min() else { return "" }
        let end = group.map { $0.location + $0.length }.max() ?? start
        let ns = text as NSString
        let from = max(0, start - padding)
        let to = min(ns.length, end + padding)
        let length = min(to - from, limit)
        guard length > 0 else { return "" }
        return ns.substring(with: NSRange(location: from, length: length))
    }

    // MARK: - 诊断

    /// 解析不出任何记录时，把日志里"看起来跟电池有关"的键名报出来，
    /// 便于直接补映射，不用猜。只在失败路径执行，不影响正常导入性能。
    private static func collectCandidateKeys(from text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "\"([A-Za-z0-9_.\\-]{0,60}(?:battery|capacity|cycle|charge|health)"
                + "[A-Za-z0-9_.\\-]{0,40})\"\\s*:",
            options: [.caseInsensitive]) else { return "" }
        let ns = text as NSString
        var seen: [String] = []
        var set = Set<String>()
        regex.enumerateMatches(in: text, options: [],
                               range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match = match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text),
                  seen.count < 30 else { return }
            let key = String(text[r])
            if set.insert(key).inserted { seen.append(key) }
        }
        return seen.joined(separator: "、")
    }

    // MARK: - 时间戳扫描

    private struct Stamp {
        let location: Int
        let raw: String
    }

    private static func timestampMatches(in text: String) -> [Stamp] {
        let patterns = [
            "\"timestamp\"\\s*:\\s*\"([^\"]+)\"",
            "\"(created_at|CreationDate|date)\"\\s*:\\s*\"([^\"]+)\""
        ]
        var out: [Stamp] = []
        for (i, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            let groupIndex = (i == 1) ? 2 : 1
            let ns = text as NSString
            regex.enumerateMatches(in: text, options: [],
                                   range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match = match, match.numberOfRanges > groupIndex,
                      let r = Range(match.range(at: groupIndex), in: text) else { return }
                out.append(Stamp(location: match.range.location, raw: String(text[r])))
            }
        }
        return out.sorted { $0.location < $1.location }
    }

    /// Daily 聚合日志的「数据对应日期」：取 metadata 行的 startTimestamp。
    ///
    /// 这类日志表头 `timestamp` 是文件生成时刻（通常次日早上 8 点），
    /// 电池统计实际对应 `startTimestamp` 那天（如 `2026-09-24T00:00:00Z` → 9 月 24 日）。
    /// 若电池行没有自带日期，用它代替表头时间戳，避免记录被推到生成日。
    private static func fileStartDate(from text: String) -> Date? {
        let prefix = String(text.prefix(50_000))
        guard let regex = try? NSRegularExpression(
            pattern: "\"startTimestamp\"\\s*:\\s*\"([^\"]+)\""),
              let m = regex.firstMatch(in: prefix,
                                       range: NSRange(location: 0, length: prefix.count)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: prefix)
        else { return nil }
        return parseDateString(String(prefix[r]))
    }

    /// 取该位置之前最近的一个时间戳；一个文件 = 一天，电池行就用表头那个时间
    private static func nearestDate(before location: Int, in stamps: [Stamp]) -> Date? {
        for s in stamps.reversed() where s.location <= location {
            if let d = parseDateString(s.raw) { return d }
        }
        return nil
    }

    private static func firstStamp(in stamps: [Stamp]) -> Date? {
        for s in stamps where parseDateString(s.raw) != nil {
            return parseDateString(s.raw)
        }
        return nil
    }

    // MARK: - 时间解析

    /// 支持 .ips 首行的 `2026-09-24 08:00:08.00 +0800`、ISO8601 等。
    ///
    /// ⚠️ 小数秒位数在不同 iOS 版本上是 1~6 位都有（实测 `08:00:08.00` 是两位），
    /// 只写死 `.SSSS` / `.SSSSSS` 会全部匹配失败 → 日期回退成"导入时刻"，
    /// 所有记录挤在同一天，趋势图直接废掉。
    /// Swift 6：`parse` 会被 `Task.detached` 在后台线程调用，静态 DateFormatter 缓存
    /// 需显式 `nonisolated(unsafe)`（DateFormatter 内部有锁，实例只读，跨线程安全）。
    private nonisolated(unsafe) static let dateFormatters: [DateFormatter] = {
        let fractions = ["", ".S", ".SS", ".SSS", ".SSSS", ".SSSSS", ".SSSSSS"]
        let zones = ["Z", ""]
        var patterns: [String] = []
        for f in fractions {
            for z in zones {
                patterns.append("yyyy-MM-dd HH:mm:ss\(f)\(z)")
                patterns.append("yyyy-MM-dd'T'HH:mm:ss\(f)\(z)")
            }
        }
        patterns.append("yyyy-MM-dd")
        return patterns.map { p in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone.current
            f.dateFormat = p
            return f
        }
    }()

    private static func parseDateString(_ s: String) -> Date? {
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // 1) ISO8601（含 / 不含小数秒）
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: cleaned) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: cleaned) { return d }

        // 2) 多格式 DateFormatter
        for f in dateFormatters {
            if let d = f.date(from: cleaned) { return d }
        }

        // 3) 手写兜底：不依赖位数，直接抓数字
        return manualDate(cleaned)
    }

    /// 手写解析 `YYYY-MM-DD[ T]HH:MM[:SS][.fraction][ Z|+0800]`，秒、小数、时区都可选
    private static func manualDate(_ s: String) -> Date? {
        let pattern = "(\\d{4})-(\\d{2})-(\\d{2})[ T](\\d{2}):(\\d{2})(?::(\\d{2}))?"
            + "(?:\\.(\\d+))?\\s*(?:(Z)|([+-])(\\d{2}):?(\\d{2}))?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length))
        else { return nil }

        func int(_ i: Int) -> Int? {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
            return Int(s[range])
        }
        func str(_ i: Int) -> String? {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
            return String(s[range])
        }

        guard let year = int(1), let month = int(2), let day = int(3),
              let hour = int(4), let minute = int(5) else { return nil }
        let second = int(6) ?? 0

        var offset = TimeZone.current.secondsFromGMT()
        if str(8) != nil {
            offset = 0                // Z
        } else if let sign = str(9), let th = int(10), let tm = int(11) {
            offset = (sign == "-" ? -1 : 1) * (th * 3600 + tm * 60)
        }

        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: offset)
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        return comps.date
    }
}
