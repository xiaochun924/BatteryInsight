import Foundation
import UIKit
import Combine

/// 封装 UIDevice 电池监控：开启监控、定时采样、监听系统电量/状态变化通知。
///
/// 平台限制提示：
/// - iOS 只允许第三方 App 读取「当前电量」与「充电状态」，
///   「最大容量 / 循环次数」属私有 API，不可用（上架会被拒）。
/// - App 进入后台会被挂起，定时器与通知都会暂停，
///   因此采样只在**前台**持续有效；后台时段的数据为空属于正常现象。
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level: Float = -1              // 0.0~1.0，<0 表示未知
    @Published private(set) var state: UIDevice.BatteryState = .unknown

    /// 采样间隔（秒），默认 60s
    var samplingInterval: TimeInterval = 60

    /// 每产生一个有效采样点时回调
    var onSample: ((BatterySample) -> Void)?
    /// 充电状态发生变化时回调（旧状态, 新状态, 时间）
    var onStateChange: ((BatteryStateKind, BatteryStateKind, Date) -> Void)?

    private var timer: Timer?
    private var bag = Set<AnyCancellable>()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true

        // Swift 6：`.receive(on: RunLoop.main)` 保证回调发生在主 RunLoop，
        // 但编译器仍视为非隔离闭包，访问 @MainActor 的 self 需显式跳回主线程。
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.capture(reason: .system) }
            }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.capture(reason: .system) }
            }
            .store(in: &bag)
    }

    func start() {
        capture(reason: .launch)
        timer?.invalidate()
        // Timer 的 block 是 @Sendable，会在主 RunLoop 触发，但编译器按非隔离对待，
        // 因此这里用 assumeIsolated 在主线程上执行采样（Timer 本就调度在主线程）。
        timer = Timer.scheduledTimer(withTimeInterval: samplingInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture(reason: .timer) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 立即采样一次（会更新 level/state，并在有效时回调）
    func capture(reason: SampleReason) {
        let newLevel = UIDevice.current.batteryLevel
        let newRawState = UIDevice.current.batteryState
        let prevState = BatteryStateKind(state)

        level = newLevel
        state = newRawState

        // 模拟器或未知设备返回 -1，此时不落库，避免污染统计
        guard newLevel >= 0 else { return }

        let newState = BatteryStateKind(newRawState)
        let sample = BatterySample(date: Date(),
                                   level: Double(newLevel),
                                   state: newState,
                                   reason: reason)
        onSample?(sample)

        if prevState != newState {
            onStateChange?(prevState, newState, Date())
        }
    }
}
