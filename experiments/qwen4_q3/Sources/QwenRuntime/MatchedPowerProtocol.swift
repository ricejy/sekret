import Foundation

/// Fixed development protocol; never a production battery-life promise.
public enum MatchedPowerProtocol {
    public static let phaseSeconds: TimeInterval = 300
    public static let maximumWorkloadSeconds: TimeInterval = 300
    public enum Order: String, Codable { case baselineFirst = "baseline-first", workloadFirst = "workload-first" }

    public static func order(arguments: [String]) throws -> Order? {
        let flags = arguments.filter { $0.hasPrefix("--power-matched=") }
        guard !flags.isEmpty else { return nil }
        guard flags.count == 1, arguments.contains("--power-profile"),
              arguments.contains("--long-chat"),
              let order = Order(rawValue: String(flags[0].dropFirst("--power-matched=".count))) else {
            throw EvaluationError.invalid("Matched power requires one fixed order, --power-profile and --long-chat.")
        }
        return order
    }

    public static func remaining(start: TimeInterval, now: TimeInterval) throws -> TimeInterval {
        guard start.isFinite, now.isFinite, now >= start else {
            throw EvaluationError.invalid("Invalid monotonic power clock.")
        }
        return max(0, phaseSeconds - (now - start))
    }
}
