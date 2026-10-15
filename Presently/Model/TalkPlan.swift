import Foundation

/// How long the talk may take: a duration, or an end time on the clock.
enum TalkLimit: Equatable {
    case none
    case duration(minutes: Int)
    case endTime(hour: Int, minute: Int)

    /// Time left. For an end time, the next occurrence that's at most 12 h in the past (a talk
    /// running over is negative, not "tomorrow").
    func remaining(elapsed: TimeInterval, now: Date, calendar: Calendar = .current) -> TimeInterval? {
        switch self {
        case .none:
            return nil
        case .duration(let minutes):
            return TimeInterval(minutes * 60) - elapsed
        case .endTime(let hour, let minute):
            guard var end = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
            if end.timeIntervalSince(now) < -12 * 3600 { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
            return end.timeIntervalSince(now)
        }
    }
}

enum TalkPlan {
    /// Ahead (+) or behind (−) schedule. `progress` = share of the talk's slides already done
    /// (0 on the first slide). The planned total is elapsed + remaining, so it works for a
    /// duration as well as for an end time.
    static func paceOffset(elapsed: TimeInterval, remaining: TimeInterval, progress: Double) -> TimeInterval {
        progress * max(0, elapsed + remaining) - elapsed
    }

    /// Talk progress at a page: slides (overlay groups) before the current one, divided by
    /// the slides of the talk (up to `endPage`). nil for backup pages after the end.
    static func progress(at index: Int, labels: [String], endPage: Int?) -> Double? {
        let last = min(endPage ?? labels.count - 1, labels.count - 1)
        guard index <= last, last >= 0 else { return nil }
        var slides = 0, done = 0
        for i in 0...last where i == 0 || labels[i] != labels[i - 1] {
            if i <= index { done = slides }
            slides += 1
        }
        return slides > 0 ? Double(done) / Double(slides) : nil
    }

    static func formatPace(_ offset: TimeInterval) -> String {
        if abs(offset) < 30 { return String(localized: "on schedule") }
        let text = PresentationTimer.format(abs(offset))
        return offset > 0 ? String(localized: "\(text) ahead") : String(localized: "\(text) behind")
    }
}

/// Last shown page per PDF (by path), so reopening continues there. Kept in UserDefaults, not
/// in the sidecar — otherwise just looking at a PDF would create a .pdfpc file.
struct LastPageStore {
    static let key = "lastPages"
    static let limit = 100
    var defaults: UserDefaults = .standard

    func page(for url: URL) -> Int? {
        (defaults.dictionary(forKey: Self.key)?[url.standardizedFileURL.path] as? [Any])?.first as? Int
    }

    /// Entries are [page, timestamp]; the oldest are dropped beyond `limit`.
    func set(_ page: Int, for url: URL, now: Date = Date()) {
        var all = defaults.dictionary(forKey: Self.key) ?? [:]
        all[url.standardizedFileURL.path] = [page, now.timeIntervalSince1970]
        if all.count > Self.limit {
            let oldest = all.sorted { ((($0.value as? [Any])?.last as? Double) ?? 0) < ((($1.value as? [Any])?.last as? Double) ?? 0) }
            for (k, _) in oldest.prefix(all.count - Self.limit) { all[k] = nil }
        }
        defaults.set(all, forKey: Self.key)
    }
}
