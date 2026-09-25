import Foundation

/// 机型 → 出厂（设计）容量对照表。
///
/// ## 为什么需要它
///
/// iOS 26 的分析日志电池段（`BatteryConfigValueHistogram`）里**没有
/// `DesignCapacity` 键**，只有 `NominalChargeCapacity`（当前标称容量）与
/// `AppleRawMaxCapacity`（实时实测容量）。所以「出厂容量」这一项无法从日志读出，
/// 只能按机型取官方标称值 —— 这正是主流电池工具的「出厂容量」来源
/// （例：iPhone 17 Pro Max = 4823 mAh）。
///
/// ## 健康度口径
///
/// 出厂容量 = 本表按机型查得；额定容量 = 日志里的 `NominalChargeCapacity`。
/// 健康度 = 额定 ÷ 出厂，量级与系统 MaximumCapacityPercent 一致
/// （例如 4900 ÷ 4823 ≈ 101.6%，系统显示 103%）。
///
/// ⚠️ 机型识别不出来的设备**一律返回 nil**，UI 就不显示该项——
/// 宁可留空，也不要按猜测给一个看起来合理的错数字。
enum DeviceBatterySpec {

    struct Spec: Sendable {
        /// 市场名，如「iPhone 17 Pro Max」
        let marketingName: String
        /// 官方标称出厂容量（mAh）
        let factoryCapacity: Int
    }

    /// 机型标识符（`hw.machine`，如 `iPhone18,2`）→ 出厂规格
    private static let table: [String: Spec] = [
        // iPhone 6s / 7 / 8 / X
        "iPhone8,1": Spec(marketingName: "iPhone 6s", factoryCapacity: 1715),
        "iPhone8,2": Spec(marketingName: "iPhone 6s Plus", factoryCapacity: 2750),
        "iPhone9,1": Spec(marketingName: "iPhone 7", factoryCapacity: 1960),
        "iPhone9,3": Spec(marketingName: "iPhone 7", factoryCapacity: 1960),
        "iPhone9,2": Spec(marketingName: "iPhone 7 Plus", factoryCapacity: 2900),
        "iPhone9,4": Spec(marketingName: "iPhone 7 Plus", factoryCapacity: 2900),
        "iPhone10,1": Spec(marketingName: "iPhone 8", factoryCapacity: 1821),
        "iPhone10,4": Spec(marketingName: "iPhone 8", factoryCapacity: 1821),
        "iPhone10,2": Spec(marketingName: "iPhone 8 Plus", factoryCapacity: 2675),
        "iPhone10,5": Spec(marketingName: "iPhone 8 Plus", factoryCapacity: 2675),
        "iPhone10,3": Spec(marketingName: "iPhone X", factoryCapacity: 2716),
        "iPhone10,6": Spec(marketingName: "iPhone X", factoryCapacity: 2716),
        // XS / XR
        "iPhone11,2": Spec(marketingName: "iPhone XS", factoryCapacity: 2658),
        "iPhone11,4": Spec(marketingName: "iPhone XS Max", factoryCapacity: 3174),
        "iPhone11,6": Spec(marketingName: "iPhone XS Max", factoryCapacity: 3174),
        "iPhone11,8": Spec(marketingName: "iPhone XR", factoryCapacity: 2942),
        // iPhone 11 / SE2
        "iPhone12,1": Spec(marketingName: "iPhone 11", factoryCapacity: 3110),
        "iPhone12,3": Spec(marketingName: "iPhone 11 Pro", factoryCapacity: 3046),
        "iPhone12,5": Spec(marketingName: "iPhone 11 Pro Max", factoryCapacity: 3969),
        "iPhone12,8": Spec(marketingName: "iPhone SE (2nd)", factoryCapacity: 1821),
        // iPhone 12
        "iPhone13,1": Spec(marketingName: "iPhone 12 mini", factoryCapacity: 2227),
        "iPhone13,2": Spec(marketingName: "iPhone 12", factoryCapacity: 2815),
        "iPhone13,3": Spec(marketingName: "iPhone 12 Pro", factoryCapacity: 2815),
        "iPhone13,4": Spec(marketingName: "iPhone 12 Pro Max", factoryCapacity: 3687),
        // iPhone 13 / SE3
        "iPhone14,2": Spec(marketingName: "iPhone 13 Pro", factoryCapacity: 3095),
        "iPhone14,3": Spec(marketingName: "iPhone 13 Pro Max", factoryCapacity: 4352),
        "iPhone14,4": Spec(marketingName: "iPhone 13 mini", factoryCapacity: 2406),
        "iPhone14,5": Spec(marketingName: "iPhone 13", factoryCapacity: 3240),
        "iPhone14,6": Spec(marketingName: "iPhone SE (3rd)", factoryCapacity: 2018),
        // iPhone 14
        "iPhone14,7": Spec(marketingName: "iPhone 14", factoryCapacity: 3279),
        "iPhone14,8": Spec(marketingName: "iPhone 14 Plus", factoryCapacity: 4325),
        "iPhone15,2": Spec(marketingName: "iPhone 14 Pro", factoryCapacity: 3200),
        "iPhone15,3": Spec(marketingName: "iPhone 14 Pro Max", factoryCapacity: 4323),
        // iPhone 15
        "iPhone15,4": Spec(marketingName: "iPhone 15", factoryCapacity: 3349),
        "iPhone15,5": Spec(marketingName: "iPhone 15 Plus", factoryCapacity: 4383),
        "iPhone16,1": Spec(marketingName: "iPhone 15 Pro", factoryCapacity: 3274),
        "iPhone16,2": Spec(marketingName: "iPhone 15 Pro Max", factoryCapacity: 4441),
        // iPhone 16
        "iPhone17,1": Spec(marketingName: "iPhone 16 Pro", factoryCapacity: 3582),
        "iPhone17,2": Spec(marketingName: "iPhone 16 Pro Max", factoryCapacity: 4685),
        "iPhone17,3": Spec(marketingName: "iPhone 16", factoryCapacity: 3561),
        "iPhone17,4": Spec(marketingName: "iPhone 16 Plus", factoryCapacity: 4674),
        // iPhone 17 系列（Pro Max 实体 SIM 版 4823 / eSIM 版 5088，取国内在售的实体卡版本）
        "iPhone18,1": Spec(marketingName: "iPhone 17 Pro", factoryCapacity: 4252),
        "iPhone18,2": Spec(marketingName: "iPhone 17 Pro Max", factoryCapacity: 4823),
        "iPhone18,3": Spec(marketingName: "iPhone 17", factoryCapacity: 3692),
        "iPhone18,4": Spec(marketingName: "iPhone Air", factoryCapacity: 3142),
    ]

    /// 本机机型标识符，如 `iPhone18,2`；模拟器返回 `x86_64` / `arm64`
    static var machineIdentifier: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    /// 本机的出厂规格；机型不在表里时返回 nil（不猜）
    static var current: Spec? { table[machineIdentifier] }
}
