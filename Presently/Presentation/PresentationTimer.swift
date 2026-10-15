import Foundation

/// Elapsed talk time that can be paused. Value type; the caller passes the current time.
struct PresentationTimer: Equatable {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    var isRunning: Bool { runningSince != nil }

    func elapsed(at now: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    mutating func start(at now: Date) {
        if runningSince == nil { runningSince = now }
    }

    mutating func pause(at now: Date) {
        accumulated = elapsed(at: now)
        runningSince = nil
    }

    mutating func toggle(at now: Date) {
        isRunning ? pause(at: now) : start(at: now)
    }

    /// Back to zero; keeps running if it was.
    mutating func reset(at now: Date) {
        accumulated = 0
        runningSince = isRunning ? now : nil
    }

    static func format(_ interval: TimeInterval) -> String {
        let negative = interval < 0
        let seconds = Int(abs(interval).rounded(.down))
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        let text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
        return negative ? "−" + text : text
    }
}
