import Foundation

/// iOS 分析日志（Analytics-*.ips）电池数据解析器。
///
/// ## 真实结构
///
/// 一个 `.ips` 是「一行元数据头 + 一行 JSON 正文」，系统写入的电池快照在正文的
/// `batteryhealth` 对象里：
///
/// ```
/// {"timestamp":"2026-09-19 10:23:45.6780 +0800","bug_type":"115","os_version":"iPhone OS 26.0 (23A340)"}
/// {"batteryhealth":{"CycleCount":123,"DesignCapacity":4823,"MaximumCapacityPercent":100,
///   "NominalChargeCapacity":4906,"Voltage":4.2,"Temperature":30.5,...},"osVersion":"iPhone OS 26.0"}
/// ```
///
/// ## 解析策略：结构优先，正则兜底
///
/// 1. **结构化解析（主路径）**：按花括号配平切出顶层 JSON 对象 → `JSONSerialization`
///    → 递归定位 `batteryhealth` → 按类型取值。字段归属明确，不会串值，
///    也不用猜哪个数字属于哪个键。
/// 2. **宽松正则（兜底）**：JSON 解析失败（截断、用户只复制了片段）时，
///    退回按位置聚类的字段扫描，保证「有字段就能解析出来」。
///
/// 多份日志拼接时，正文对象往往自带时间戳；不带的话取它**之前最近一个**
/// 带 timestamp 的对象的日期，而不是导入时刻。
enum AnalyticsLogParser {

    // MARK: - 对外入口

    static func parse(_ text: String) -> AnalyticsParseResult {
        var result = AnalyticsParseResult()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.warnings.append("输入为空，请先粘贴日志内容")
            return result
        }

        let objects = topLevelJSONObjects(in: text)
        var records: [AnalyticsRecord] = []

        // —— 主路径：结构化解析
        if !objects.isEmpty {
            result.entriesFound = objects.count
            var carryDate: Date?
            for raw in objects {
                guard let object = dictionary(from: raw) else { continue }
                // 头对象只有时间戳，正文对象才有电池数据：把时间戳往后带
                if let d = extractDate(from: object) { carryDate = d }
                if let r = record(from: object, fallbackDate: carryDate, raw: raw) {
                    records.append(r)
                }
            }
        }

        // —— 兜底：宽松正则扫描（截断 / 拼接残片 / 非 JSON 文本）
        if records.isEmpty {
            let fallback = scanFallback(text)
            records = fallback.records
            result.entriesFound = max(result.entriesFound, fallback.entriesFound)
            if !records.isEmpty {
                result.warnings.append("未能按 JSON 结构解析（日志可能被截断），已改用字段扫描")
            }
        }

        // 去重：同一时间戳 + 同一健康度只保留一条
        var seen = Set<String>()
        records = records.filter { r in
            let key = "\(Int(r.date.timeIntervalSince1970))-\(r.systemHealthPercent ?? -1)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        records.sort { $0.date < $1.date }
        result.records = records

        if records.isEmpty {
            result.warnings.append(
                "未识别到电池字段。请确认导入的是「分析数据」中 Analytics-*.ips 文件的内容，"
                + "且包含 batteryhealth 段落。")
        } else if records.count == 1 && result.entriesFound > 1 {
            result.warnings.append("多条日志中仅 1 条含电池数据，通常属正常（该段落非每次采样都写入）")
        }

        return result
    }

    // MARK: - 顶层 JSON 对象切分

    /// 按花括号配平切出顶层 JSON 对象，正确处理字符串内的 `{` `}` 与转义。
    private static func topLevelJSONObjects(in text: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for idx in text.indices {
            let c = text[idx]
            if inString {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString = false
                }
                continue
            }
            switch c {
            case "\"":
                inString = true
            case "{":
                if depth == 0 { start = idx }
                depth += 1
            case "}":
                depth -= 1
                if depth <= 0, let s = start {
                    let piece = String(text[s...idx])
                    if piece.count >= 2 { out.append(piece) }
                    start = nil
                    depth = 0
                }
            default:
                break
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

    // MARK: - 定位 batteryhealth

    /// 不同 iOS 版本大小写与命名略有差异
    private static let batterySectionKeys: Set<String> = [
        "batteryhealth", "battery_health", "batteryhealthdata", "batterydata"
    ]

    /// 递归查找 `batteryhealth` 对象；找不到但顶层就带电池字段时，直接返回顶层
    private static func batterySource(in object: [String: Any]) -> [String: Any]? {
        if let direct = findBatterySection(in: object) { return direct }
        return hasBatteryKey(object) ? object : nil
    }

    private static func findBatterySection(in object: [String: Any]) -> [String: Any]? {
        for (key, value) in object where batterySectionKeys.contains(key.lowercased()) {
            if let dict = value as? [String: Any] { return dict }
        }
        // 下钻一层：个别版本把电池数据放在 payload / data 之类的容器里
        for (_, value) in object {
            if let nested = value as? [String: Any],
               let found = findBatterySection(in: nested) { return found }
        }
        return nil
    }

    private static func hasBatteryKey(_ object: [String: Any]) -> Bool {
        object.keys.contains { key in
            knownKeys.contains { $0.caseInsensitiveCompare(key) == .orderedSame }
        }
    }

    // MARK: - 字段定义

    /// 已单独建模的字段（按语义分组，组内按优先级）
    private static let healthKeys = ["MaximumCapacityPercent", "maximum_capacity_percent",
                                     "SystemHealthPercent", "design_capacity_percent"]
    private static let cycleKeys = ["CycleCount", "cycle_count",
                                    "CycleCountTotal", "TotalCycleCount"]
    private static let nominalKeys = ["NominalChargeCapacity", "nominal_charge_capacity",
                                      "NominalChargeCapacityMah"]
    private static let designKeys = ["DesignCapacity", "design_capacity",
                                     "NominalChargeCapacityDesign", "DesignCapacityMah"]
    private static let voltageKeys = ["Voltage", "BatteryVoltage", "battery_voltage"]
    private static let tempKeys = ["Temperature", "BatteryTemperature", "battery_temperature"]

    /// 所有已知键，用于判断某个对象是否是「电池对象」
    private static var knownKeys: [String] {
        healthKeys + cycleKeys + nominalKeys + designKeys + voltageKeys + tempKeys
    }

    /// 已从 batteryhealth 单独建模的键（小写集合），其余数值进 extraFields
    private static var modeledKeys: Set<String> {
        Set(knownKeys.map { $0.lowercased() })
    }

    // MARK: - 组装记录

    private static func record(from object: [String: Any],
                               fallbackDate: Date?,
                               raw: String) -> AnalyticsRecord? {
        guard let battery = batterySource(in: object) else { return nil }

        let health = double(in: battery, healthKeys)
        let cycles = double(in: battery, cycleKeys).map { Int($0) }
        let nominal = double(in: battery, nominalKeys).map { Int($0) }
        let design = double(in: battery, designKeys).map { Int($0) }
        let voltage = double(in: battery, voltageKeys)
        let temperature = double(in: battery, tempKeys)

        let record = AnalyticsRecord(
            date: extractDate(from: object) ?? fallbackDate ?? Date(),
            systemHealthPercent: health,
            cycleCount: cycles,
            nominalChargeCapacity: nominal,
            designCapacity: design,
            voltage: voltage,
            temperature: temperature,
            rawSnippet: String(raw.prefix(4000)),
            extraFields: extraNumericFields(in: battery))

        return record.hasAnyMetric ? record : nil
    }

    /// 收集 batteryhealth 里未被单独建模的数值字段。
    /// 系统写什么就存什么（AppleRawMaxCapacity、Qmax、WeightedRa、PresentDOD…），
    /// 不同机型字段集合本就不同，不建模也不能丢。
    private static func extraNumericFields(in battery: [String: Any]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, value) in battery {
            guard !modeledKeys.contains(key.lowercased()) else { continue }
            if let v = numeric(value) { out[key] = v }
        }
        return out
    }

    // MARK: - 取值

    /// 依次尝试给定键，命中即返回；支持忽略大小写匹配
    private static func double(in dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            if let v = value(of: key, in: dict) { return v }
        }
        return nil
    }

    private static func value(of key: String, in dict: [String: Any]) -> Double? {
        if let v = numeric(dict[key]) { return v }
        for (k, val) in dict where k.caseInsensitiveCompare(key) == .orderedSame {
            if let v = numeric(val) { return v }
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

    // MARK: - 兜底：宽松正则扫描

    private enum MetricGroup { case health, cycle, nominal, design, voltage, temperature }

    private struct FieldMatch {
        let group: MetricGroup
        let key: String
        let value: Double
        let location: Int
        let length: Int
    }

    private struct FallbackResult {
        var records: [AnalyticsRecord] = []
        var entriesFound: Int = 0
    }

    /// JSON 结构化解析失败时的退路：按位置聚类，尽力把字段聚成一条条记录
    private static func scanFallback(_ text: String) -> FallbackResult {
        var out = FallbackResult()

        let matches = allFieldMatches(in: text)
        let clusters = cluster(matches)
        let stamps = timestampMatches(in: text)
        out.entriesFound = stamps.isEmpty ? clusters.count : stamps.count

        for group in clusters {
            guard let start = group.map(\.location).min() else { continue }
            let date = nearestDate(before: start, in: stamps) ?? Date()
            let health = pick(.health, from: group)
            let cycles = pick(.cycle, from: group).map { Int($0) }
            let nominal = pick(.nominal, from: group).map { Int($0) }
            let design = pick(.design, from: group).map { Int($0) }
            let voltage = pick(.voltage, from: group)
            let temperature = pick(.temperature, from: group)

            let record = AnalyticsRecord(
                date: date,
                systemHealthPercent: health,
                cycleCount: cycles,
                nominalChargeCapacity: nominal,
                designCapacity: design,
                voltage: voltage,
                temperature: temperature,
                rawSnippet: snippet(around: group, in: text))

            if record.hasAnyMetric { out.records.append(record) }
        }
        return out
    }

    private static func allFieldMatches(in text: String) -> [FieldMatch] {
        let groups: [(MetricGroup, [String])] = [
            (.health, healthKeys), (.cycle, cycleKeys), (.nominal, nominalKeys),
            (.design, designKeys), (.voltage, voltageKeys), (.temperature, tempKeys)
        ]
        var out: [FieldMatch] = []
        for (group, keys) in groups {
            var found: [FieldMatch] = []
            for key in keys {
                let quoted = "\"\(key)\"\\s*:\\s*\"?(-?[0-9]+\\.?[0-9]*(?:[eE][-+]?[0-9]+)?)\"?"
                found.append(contentsOf: scan(pattern: quoted, in: text, group: group, key: key))
            }
            if found.isEmpty {
                for key in keys {
                    let bare = "\\b\(key)\\b\\s*[:=]\\s*\"?(-?[0-9]+\\.?[0-9]*)\"?"
                    found.append(contentsOf: scan(pattern: bare, in: text, group: group, key: key))
                }
            }
            out.append(contentsOf: found)
        }
        return out
    }

    private static func scan(pattern: String,
                             in text: String,
                             group: MetricGroup,
                             key: String) -> [FieldMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        var out: [FieldMatch] = []
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match, match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[valueRange]) else { return }
            out.append(FieldMatch(group: group, key: key, value: value,
                                  location: match.range.location, length: match.range.length))
        }
        return out
    }

    /// 切分信号：间隔过远，或同一键重复出现（一个 batteryhealth 里同键不会出现两次）
    private static func cluster(_ matches: [FieldMatch], maxGap: Int = 2000) -> [[FieldMatch]] {
        guard !matches.isEmpty else { return [] }
        let sorted = matches.sorted { $0.location < $1.location }
        var clusters: [[FieldMatch]] = []
        var current: [FieldMatch] = [sorted[0]]
        var last = sorted[0].location

        for m in sorted.dropFirst() {
            let tooFar = m.location - last > maxGap
            let repeated = current.contains { $0.group == m.group && $0.key == m.key }
            if tooFar || repeated {
                clusters.append(current)
                current = []
            }
            current.append(m)
            last = m.location
        }
        clusters.append(current)
        return clusters
    }

    private static func pick(_ group: MetricGroup, from cluster: [FieldMatch]) -> Double? {
        for key in keys(for: group) {
            if let m = cluster.first(where: { $0.group == group && $0.key == key }) {
                return m.value
            }
        }
        return nil
    }

    private static func keys(for group: MetricGroup) -> [String] {
        switch group {
        case .health: return healthKeys
        case .cycle: return cycleKeys
        case .nominal: return nominalKeys
        case .design: return designKeys
        case .voltage: return voltageKeys
        case .temperature: return tempKeys
        }
    }

    private static func snippet(around cluster: [FieldMatch],
                                in text: String,
                                padding: Int = 600,
                                limit: Int = 4000) -> String {
        guard let start = cluster.map(\.location).min() else { return "" }
        let ends = cluster.map { $0.location + $0.length }
        guard let end = ends.max() else { return "" }
        let ns = text as NSString
        let from = max(0, start - padding)
        let to = min(ns.length, end + padding)
        let length = min(to - from, limit)
        guard length > 0 else { return "" }
        return ns.substring(with: NSRange(location: from, length: length))
    }

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
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let groupIndex = (i == 1) ? 2 : 1
            let range = NSRange(location: 0, length: (text as NSString).length)
            regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
                guard let match = match, match.numberOfRanges > groupIndex,
                      let r = Range(match.range(at: groupIndex), in: text) else { return }
                out.append(Stamp(location: match.range.location, raw: String(text[r])))
            }
        }
        return out.sorted { $0.location < $1.location }
    }

    private static func nearestDate(before location: Int, in stamps: [Stamp]) -> Date? {
        for s in stamps.reversed() where s.location <= location {
            if let d = parseDateString(s.raw) { return d }
        }
        for s in stamps where s.location > location {
            if let d = parseDateString(s.raw) { return d }
        }
        return nil
    }

    // MARK: - 时间解析

    /// 支持 .ips 首行的 `2026-09-19 10:23:45.6780 +0800`、ISO8601、`2026-09-19 10:23:45` 等
    private static let dateFormatters: [DateFormatter] = {
        let patterns = [
            "yyyy-MM-dd HH:mm:ss.SSSSZ",
            "yyyy-MM-dd HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd"
        ]
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
        for f in dateFormatters {
            if let d = f.date(from: cleaned) { return d }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: cleaned) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: cleaned)
    }
}
