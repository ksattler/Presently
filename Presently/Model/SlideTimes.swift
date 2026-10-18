import Foundation

/// How long the audience saw each slide during a presentation, in talk time: the
/// `PresentationTimer`'s elapsed time, so pauses (and waiting for the first page turn) don't
/// count. Slides are keyed by the first page of their overlay group. Kept in memory only.
struct SlideTimes: Equatable {
    private(set) var seconds: [Int: TimeInterval] = [:]
    /// Slide shown since timer value `mark`; nil = none (not presenting).
    private var current: Int?
    private var mark: TimeInterval = 0

    var isEmpty: Bool { seconds.values.allSatisfy { $0 <= 0 } && current == nil }

    /// The audience now sees `slide` (nil: the presentation ended); `elapsed` is the timer's value.
    mutating func enter(_ slide: Int?, elapsed: TimeInterval) {
        if let current { seconds[current, default: 0] += max(0, elapsed - mark) }
        current = slide
        mark = elapsed
    }

    /// Time on a slide, including the running visit.
    func seconds(of slide: Int, elapsed: TimeInterval) -> TimeInterval {
        seconds[slide, default: 0] + (slide == current ? max(0, elapsed - mark) : 0)
    }

    func total(elapsed: TimeInterval) -> TimeInterval {
        seconds.values.reduce(0, +) + (current != nil ? max(0, elapsed - mark) : 0)
    }
}
