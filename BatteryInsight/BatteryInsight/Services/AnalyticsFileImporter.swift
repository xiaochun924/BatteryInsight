import Foundation
import UniformTypeIdentifiers

/// 从「文件」App / 隔空投送 / 云盘里选中的分析日志文件读取文本。
///
/// 为什么需要这一层：iOS 不允许第三方 App 直接访问系统「分析数据」目录，
/// 但允许你把 `.ips` 文件先存到「文件」App，再由本 App 通过系统的
/// `.fileImporter`（文档选择器）在**用户显式授权**下读取。相比手动全选复制，
/// 这样不会漏内容，也支持一次选多个文件批量导入。
///
/// 注意：`.ips` 没有公开的 UTI，如果不把 `public.data` 放进允许类型，
/// 文档选择器里这些文件会显示为灰色不可选。
/// 文件读取失败原因。
/// Swift 的 `Result` 要求 Failure 遵循 `Error`，而 `String` 并不遵循该协议，
/// 因此用一个包装类型承载可直接展示的中文消息。
struct AnalyticsFileError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum AnalyticsFileImporter {

    // MARK: - 配置

    /// 文档选择器允许的类型。`.data` 是兜底项，用来覆盖 .ips / .log 等无公开 UTI 的扩展名。
    static let allowedContentTypes: [UTType] = {
        let candidates: [UTType] = [.json, .plainText, .text, .xml, .data]
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.identifier).inserted }
    }()

    /// 单文件读取上限。
    /// 实测系统「分析数据」里攒了几个月的 `Analytics-*.ips` 可以到几十 MB
    /// （用户设备上出现过 28 MB 的），之前定的 20 MB 会把正常日志挡在门外。
    /// 放宽到 512 MB：这已经远超任何真实日志，只用来拦明显选错的文件（如视频）；
    /// .ips 是纯文本，整份读入内存对这个量级没有压力。
    private static let maxBytes = 512 * 1024 * 1024

    // MARK: - 读取

    /// 读取单个文件的文本。
    /// 安全作用域访问失败、文件过大或编码不可识别时返回 `.failure` 而非抛异常，
    /// 这样批量导入时一个文件出问题不会中断其余文件。
    static func readText(of url: URL) -> Result<String, AnalyticsFileError> {
        // 文档选择器给出的 URL 带安全作用域，读取前必须显式开启
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > maxBytes {
                return .failure(AnalyticsFileError(
                    message: "\(url.lastPathComponent)：文件 \(size / 1024 / 1024) MB，超过 \(maxBytes / 1024 / 1024) MB 上限"))
            }
            let data = try Data(contentsOf: url)
            guard let text = decode(data) else {
                return .failure(AnalyticsFileError(
                    message: "\(url.lastPathComponent)：不是可识别的文本（非 UTF-8 / UTF-16），已跳过"))
            }
            return .success(text)
        } catch {
            return .failure(AnalyticsFileError(
                message: "\(url.lastPathComponent)：读取失败 — \(error.localizedDescription)"))
        }
    }

    /// 依次尝试常见文本编码。UTF-8 优先，兼容少数工具导出的 UTF-16。
    private static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return nil
    }
}
