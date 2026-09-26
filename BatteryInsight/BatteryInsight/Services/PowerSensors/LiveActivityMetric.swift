import Foundation

/// The metric shown on the compact (Dynamic Island) presentation of the charging
/// live activity. Kept here without the ActivityKit types so the rest of the
/// monitor can store the user's choice without linking the activity framework.
nonisolated enum LiveActivityMetric: String, Codable, Hashable, CaseIterable, Identifiable {
    case chargingPower
    case socTemperature
    case batteryTemperature
    case hottestTemperature

    var id: Self { self }
}
