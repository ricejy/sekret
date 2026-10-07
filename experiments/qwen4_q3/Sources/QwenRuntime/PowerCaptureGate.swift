import Foundation

/// Evaluation-only handshake. Elapsed time can expire a run, never release it.
/// The operator writes a run-specific receipt only after observing capture ready.
public enum PowerCaptureGate {
    public enum Decision: Equatable { case waiting, ready, expired }
    private struct Receipt: Decodable {
        let runID: String
        let captureReady: Bool
    }
    public static func decision(elapsed: TimeInterval, receipt: Data?, runID: String) -> Decision {
        guard elapsed.isFinite, elapsed >= 0, elapsed < 300 else { return .expired }
        guard let receipt, receipt.count <= 4096,
              let value = try? JSONDecoder().decode(Receipt.self, from: receipt),
              value.runID == runID, value.captureReady else { return .waiting }
        return .ready
    }
}
