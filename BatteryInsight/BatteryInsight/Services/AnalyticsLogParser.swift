import Foundation

/// iOS 分析日志（Analytics-*.ips）电池数据解析器。
///
/// 真实文件结构（两类）：
/// 1. **单条 JSON**：首行是 `{"timestamp":"...","bug_type":"..."}` 元数据，
///    次行起是完整 JSON 体，电池数据在 `batteryhealth`（部分版本为 `batteryHealth`）对象里。
/// 2. **多行 / 多条目文本**：多次导出拼接、或用户只复制了片段。
///
/// 解析策略：**先在全文里找出所有电池字段的匹配位置，再按位置聚成一簇一簇**，
/// 每一簇就是一条记录。相比「先切块、每块只取第一个值」的旧实现，这样做解决了三个问题：
/// - 一次导入含多份日志（或多个 `batteryhealth`）时，不再只产出 1 条；
/// - 每条记录的日期取「该簇之前最近的一个 timestamp」，而不是导入时刻，
///   避免所有记录都挤在今天、趋势图退化成一个点；
/// - 不再依赖「按行切分」的脆弱假设（有些 .ips 正文首行也带 `{"...","timestamp":...}`，
///   会把元数据和电池数据切到两个块里）。
///
/// 依然是**字段驱动的宽松扫描**而非严格 JSON 解析，对截断、拼接、格式变体都容错。
enum AnalyticsLogParser {

    // MARK: - 对外入口

    /// 解析日志文本（粘贴的内容，或导入的 .ips 文件内容）
    static func parse(_ text: String) -> AnalyticsParseResult {
        var result = AnalyticsParseResult()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.warnings.append("输入为空，请先粘贴日志内容")
            return result
        }

        let matches = allFieldMatches(in: text)
        let clusters = cluster(matches)
        let stamps = timestampMatches(in: text)
        result.entriesFound = stamps.isEmpty ? clusters.count : stamps.count

        var records: [AnalyticsRecord] = []
        for group in clusters {
            if let record = makeRecord(from: group, in: text, stamps: stamps) {
                records.append(record)
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
                + "且包含 batteryhealth / MaximumCapacityPercent 等字段。")
        } else if records.count == 1 && clusters.count > 1 {
            result.warnings.append("多条日志中仅 1 条含电池数据，通常属正常（该段落非每次采样都写入）")
        }

        return result
    }

    // MARK: - 字段定义

    private enum MetricGroup {
        case health, cycle, nominal, design, voltage, temperature
    }

    /// 每组内按键的优先级排列：靠前的键命中即采用（如 MaximumCapacityPercent 优先于 SystemHealthPercent）
    private static let keyGroups: [(MetricGroup, [String])] = [
        (.health, ["MaximumCapacityPercent", "maximum_capacity_percent",
                   "SystemHealthPercent", "design_capacity_percent"]),
        (.cycle, ["CycleCount", "cycle_count", "CycleCountTotal", "TotalCycleCount"]),
        (.nominal, ["NominalChargeCapacity", "nominal_charge_capacity",
                    "AppleRawMaxCapacity", "NominalChargeCapacityMah"]),
        (.design, ["DesignCapacity", "design_capacity",
                   "NominalChargeCapacityDesign", "DesignCapacityMah"]),
        (.voltage, ["Voltage", "BatteryVoltage", "battery_voltage"]),
        (.temperature, ["Temperature", "BatteryTemperature", "battery_temperature"])
    ]

    private static func keys(for group: MetricGroup) -> [String] {
        keyGroups.first { $0.0 == group }?.1 ?? []
    }

    // MARK: - 全文扫描

    private struct FieldMatch {
        let group: MetricGroup
        let key: String
        let value: Double
        /// 匹配起始位置（UTF-16 偏移）
        let location: Int
        let length: Int
    }

    /// 找出文本中**所有**电池字段匹配，保留位置供后续聚类。
    /// 旧实现只取第一个匹配，导致一个文件里多条记录会被丢掉。
    private static func allFieldMatches(in text: String) -> [FieldMatch] {
        var out: [FieldMatch] = []

        for (group, keys) in keyGroups {
            var found: [FieldMatch] = []
            // 常规："Key" : 123.45
            for key in keys {
                let quoted = "\"\(key)\"\\s*:\\s*\"?(-?[0-9]+\\.?[0-9]*(?:[eE][-+]?[0-9]+)?)\"?"
                found.append(contentsOf: scan(pattern: quoted, in: text, group: group, key: key))
            }
            // 退化：不带引号的键（部分 txt 导出），仅在该组完全没命中时才用
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

    // MARK: - 聚类

    /// 把散落的字段匹配聚成一条条记录。
    ///
    /// 两个切分信号：
    /// 1. **距离过远**：相邻匹配间隔超过 `maxGap`，说明中间隔了无关内容或换了一条日志；
    /// 2. **同键重复**：一个 `batteryhealth` 里同一个键不会出现两次，重复即代表下一条记录开始。
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

    // MARK: - 组装记录

    private static func makeRecord(from cluster: [FieldMatch],
                                   in text: String,
                                   stamps: [Stamp]) -> AnalyticsRecord? {
        func pick(_ group: MetricGroup) -> Double? {
            for key in keys(for: group) {
                if let m = cluster.first(where: { $0.group == group && $0.key == key }) {
                    return m.value
                }
            }
            return nil
        }

        let start = cluster.map(\.location).min() ?? 0

        let record = AnalyticsRecord(
            date: nearestDate(before: start, in: stamps) ?? Date(),
            systemHealthPercent: pick(.health),
            cycleCount: pick(.cycle).map { Int($0) },
            nominalChargeCapacity: pick(.nominal).map { Int($0) },
            designCapacity: pick(.design).map { Int($0) },
            voltage: pick(.voltage),
            temperature: pick(.temperature),
            rawSnippet: snippet(around: cluster, in: text))

        return record.hasAnyMetric ? record : nil
    }

    /// 截取簇前后各一段原文，便于在「原始日志」里回溯核对
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

    // MARK: - 时间戳

    private struct Stamp {
        let location: Int
        let raw: String
    }

    /// 找出全文所有时间戳及其位置
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
            // 第二个模式有两个捕获组，取第 2 组
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

    /// 取簇之前最近的一个可解析时间戳；若前面没有（用户只复制了正文片段），退而取后面的第一个
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
        // ISO8601 兜底
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: cleaned) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: cleaned)
    }
}
