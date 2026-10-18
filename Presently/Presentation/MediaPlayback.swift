import AVFoundation
import Combine

/// Videos of the page the audience sees. Own ObservableObject (like `LaserPointer`) so playback
/// doesn't re-render the presenter view. One `AVPlayer` per clip; the audience view and the
/// presenter's current slide both show it (one sound source). Leaving the page stops everything.
@MainActor
final class MediaPlayback: ObservableObject {
    struct Item: Identifiable {
        let id: Int
        let clip: MediaClip
        let player: AVPlayer
    }

    /// Page whose clips are loaded; nil = none (not presenting).
    @Published private(set) var pageIndex: Int?
    @Published private(set) var items: [Item] = []
    /// Clips showing video instead of their poster (started at least once on this visit).
    @Published private(set) var started: Set<Int> = []
    @Published private(set) var playing: Set<Int> = []

    /// Replaceable in tests.
    var makePlayer: (URL) -> AVPlayer = { AVPlayer(url: $0) }
    private var finished: Set<Int> = []
    private var endObservers: [NSObjectProtocol] = []

    /// Replaces the loaded clips (stopping the old ones) and starts the autostart ones.
    func load(_ clips: [MediaClip], page: Int?) {
        stop()
        pageIndex = page
        items = clips.enumerated().map { id, clip in
            let player = makePlayer(clip.url)
            player.actionAtItemEnd = .pause
            if let item = player.currentItem {
                if let duration = clip.duration {
                    item.forwardPlaybackEndTime = CMTime(seconds: clip.start + duration, preferredTimescale: 600)
                }
                endObservers.append(NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.didFinish(id) }
                })
            }
            return Item(id: id, clip: clip, player: player)
        }
        for item in items where item.clip.autostart { play(item.id) }
    }

    func stop() {
        items.forEach { $0.player.pause() }
        endObservers.forEach(NotificationCenter.default.removeObserver)
        endObservers = []
        items = []
        started = []
        playing = []
        finished = []
        pageIndex = nil
    }

    func toggle(_ id: Int) {
        playing.contains(id) ? pause(id) : play(id)
    }

    func play(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        // First start or after the end: from the clip's start time.
        if !started.contains(id) || finished.contains(id) { seekToStart(item) }
        finished.remove(id)
        started.insert(id)
        playing.insert(id)
        item.player.play()
    }

    func pause(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        item.player.pause()
        playing.remove(id)
    }

    /// Topmost clip at a point in PDF page space.
    func clip(atPagePoint point: CGPoint) -> Int? {
        items.last(where: { $0.clip.bounds.contains(point) })?.id
    }

    /// Played fraction between the clip's start and end (0…1), for progress bars.
    func progress(of item: Item) -> Double {
        let now = item.player.currentTime().seconds
        let end = item.clip.duration.map { item.clip.start + $0 } ?? item.player.currentItem?.duration.seconds ?? .nan
        guard now.isFinite, end.isFinite, end > item.clip.start else { return 0 }
        return min(max((now - item.clip.start) / (end - item.clip.start), 0), 1)
    }

    private func didFinish(_ id: Int) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        if item.clip.loops {
            seekToStart(item)
            item.player.play()
        } else {
            finished.insert(id)
            playing.remove(id)
        }
    }

    private func seekToStart(_ item: Item) {
        item.player.seek(to: CMTime(seconds: item.clip.start, preferredTimescale: 600),
                         toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
