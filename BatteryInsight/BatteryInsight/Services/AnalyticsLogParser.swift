import Foundation

/// iOS 分析日志（Analytics-*.ips）电池数据解析器。
///
/// 真实文件结构（两类）：
/// 1. **单条 JSON**：首行是 `{"timestamp":"...","appVersion":"..."}` 元数据，
///    次行起是完整 JSON 体，电池数据在 `batteryhealth`（部分版本为 `batteryHealth`）对象里。
/// 2. **多行 / 多条目文本**：多次导出拼接、或用户只复制了片段。
///
/// 因此解析策略是**字段名驱动的宽松扫描**，而非严格 JSON 解析：
/// 先在文本中定位电池相关键，再用容错正则抽值。这样对截断、拼接、格式变体都能工作。
enum AnalyticsLogParser {

    // MARK: - 对外入口

    /// 解析粘贴的日志文本
    static func parse(_ text: String) -> AnalyticsParseResult {
        var result = AnalyticsParseResult()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result.warnings.append("输入为空，请先粘贴日志内容")
            return result
        }

        // 尝试按 JSON 对象切分；失败则整段当作一个条目
        let chunks = jsonObjectChunks(in: text)
        result.entriesFound = chunks.count

        var records: [AnalyticsRecord] = []
        for chunk in chunks {
            if let record = parseChunk(chunk) {
                records.append(record)
            }
        }

        // 去重：同一时间戳只保留一条
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
                "未识别到电池字段。请确认粘贴的是「分析数据」中 Analytics-*.ips 文件的内容，"
                + "且包含 batteryhealth / MaximumCapacityPercent 等字段。")
        } else if records.count == 1 && chunks.count > 1 {
            result.warnings.append("多条日志中仅 1 条含电池数据，通常属正常（该段落非每次采样都写入）")
        }

        return result
    }

    // MARK: - 文本切分

    /// 按「行」切分日志条目，关键是**保留时间戳行与 JSON 体的关联**。
    ///
    /// 真实 `.ips` 的每个条目是两行：
    /// ```
    /// {"timestamp": "2026-09-19 10:23:45.6780 +0800", "bug_type": "115"}
    /// {"batteryhealth": {...}, "osVersion": "26.0"}
    /// ```
    /// 若按花括号配平独立切块，时间戳会与电池数据分家 —— 所以这里按行分组，
    /// 把「时间戳行 + 其后内容」合并成一条，直到遇见下一个时间戳行。
    private static func jsonObjectChunks(in text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 整体是合法 JSON：一次性交给字段扫描（时间戳与数据同在一处）
        if isValidJSON(trimmed) { return [trimmed] }

        let lines = trimmed.components(separatedBy: .newlines)
        var chunks: [String] = []
        var buffer: [String] = []
        var bufferHasTimestamp = false

        /// 该行是否是一条新日志的起始（含 timestamp 字段）
        func isTimestampLine(_ line: String) -> Bool {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard l.hasPrefix("{") else { return false }
            return l.range(of: "\"timestamp\"", options: .caseInsensitive) != nil
                || l.range(of: "\"Timestamp\"", options: .caseInsensitive) != nil
        }

        for line in lines {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty else { continue }

            if isTimestampLine(line) {
                // 遇到新条目：先把上一条落盘
                if !buffer.isEmpty {
                    chunks.append(buffer.joined(separator: "\n"))
                    buffer = []
                }
                bufferHasTimestamp = true
                buffer.append(line)
            } else if !buffer.isEmpty {
                // 续接当前条目（可能是 JSON 体，也可能是多行内容）
                buffer.append(line)
            } else if l.hasPrefix("{") {
                // 没有时间戳前缀的裸 JSON 片段（用户只复制了中段）
                buffer.append(line)
            } else {
                // 其他杂行：仅在有上下文时保留，避免拼进无关文本
                if bufferHasTimestamp { buffer.append(line) }
            }
        }
        if !buffer.isEmpty {
            chunks.append(buffer.joined(separator: "\n"))
        }

        // 兜底：按行切分完全失败（单行超长文本）时整体作为一块
        if chunks.isEmpty {
            chunks = [trimmed]
        }
        return chunks
    }

    private static func isValidJSON(_ s: String) -> Bool {
        guard let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    // MARK: - 单块解析

    private static func parseChunk(_ chunk: String) -> AnalyticsRecord? {
        let date = extractDate(from: chunk) ?? Date()

        let health = number(in: chunk, keys: [
            "MaximumCapacityPercent", "maximum_capacity_percent",
            "SystemHealthPercent", "design_capacity_percent"
        ])
        let cycles = int(in: chunk, keys: [
            "CycleCount", "cycle_count", "CycleCountTotal", "TotalCycleCount"
        ])
        let nominal = int(in: chunk, keys: [
            "NominalChargeCapacity", "nominal_charge_capacity",
            "AppleRawMaxCapacity", "NominalChargeCapacityMah"
        ])
        let design = int(in: chunk, keys: [
            "DesignCapacity", "design_capacity",
            "NominalChargeCapacityDesign", "DesignCapacityMah"
        ])
        let volt = number(in: chunk, keys: [
            "Voltage", "BatteryVoltage", "battery_voltage"
        ])
        let temp = number(in: chunk, keys: [
            "Temperature", "BatteryTemperature", "battery_temperature"
        ])

        let snippet = String(chunk.prefix(4000))
        let record = AnalyticsRecord(
            date: date,
            systemHealthPercent: health,
            cycleCount: cycles,
            nominalChargeCapacity: nominal,
            designCapacity: design,
            voltage: volt,
            temperature: temp,
            rawSnippet: snippet)

        return record.hasAnyMetric ? record : nil
    }

    // MARK: - 字段抽取

    /// 抽取 "key" : 123.45 形式的数值；支持带引号的数字
    private static func number(in text: String, keys: [String]) -> Double? {
        for key in keys {
            let pattern = "\"\(key)\"\\s*:\\s*\"?(-?[0-9]+\\.?[0-9]*(?:[eE][-+]?[0-9]+)?)\"?"
            if let v = firstMatchDouble(pattern: pattern, in: text) { return v }
        }
        // 退化：不带引号的键（部分 txt 导出）
        for key in keys {
            let pattern = "\\b\(key)\\b\\s*[:=]\\s*\"?(-?[0-9]+\\.?[0-9]*)\"?"
            if let v = firstMatchDouble(pattern: pattern, in: text) { return v }
        }
        return nil
    }

    private static func int(in text: String, keys: [String]) -> Int? {
        guard let d = number(in: text, keys: keys) else { return nil }
        return Int(d)
    }

    private static func firstMatchDouble(pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, options: [], range: range),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }

    // MARK: - 时间抽取

    /// 尝试多种时间格式：
    /// - .ips 首行 `"timestamp":"2026-09-19 10:23:45.6780 +0800"`
    /// - ISO8601 `2026-09-19T10:23:45Z`
    /// - `2026-09-19 10:23:45`
    private static func extractDate(from text: String) -> Date? {
        let candidates = [
            "\"timestamp\"\\s*:\\s*\"([^\"]+)\"",
            "\"timestamp\"\\s*:\\s*\"([0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9:]{8})",
            "\"(created_at|CreationDate|date)\"\\s*:\\s*\"([^\"]+)\""
        ]
        for (i, pattern) in candidates.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let m = regex.firstMatch(in: text, options: [], range: range) else { continue }
            // 第三个模式有两个捕获组，取第 2 组
            let groupIndex = (i == 2) ? 2 : 1
            guard let r = Range(m.range(at: groupIndex), in: text) else { continue }
            if let date = parseDateString(String(text[r])) { return date }
        }
        return nil
    }

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
