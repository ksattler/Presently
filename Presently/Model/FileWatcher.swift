import Foundation

/// Calls `onChange` when the file at `url` changes — written in place, or replaced via
/// rename/delete (as LaTeX tool chains and editors with atomic saves do). Events are debounced:
/// pdflatex writes its output in many chunks, `onChange` fires once after it has gone quiet.
@MainActor
final class FileWatcher {
    let url: URL
    private let debounce: Duration
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?
    private var reopen: Task<Void, Never>?

    init(url: URL, debounce: Duration = .milliseconds(500), onChange: @escaping () -> Void) {
        self.url = url
        self.debounce = debounce
        self.onChange = onChange
        start()
    }

    deinit {
        source?.cancel()
        pending?.cancel()
        reopen?.cancel()
    }

    func stop() {
        source?.cancel()
        source = nil
        pending?.cancel()
        reopen?.cancel()
    }

    private func start() {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Replaced file not there yet: try again shortly.
            reopen = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.start()
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.handle(src.data) }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func handle(_ event: DispatchSource.FileSystemEvent) {
        if !event.isDisjoint(with: [.delete, .rename]) {
            // The descriptor still points at the old file: watch the new one at the same path.
            source?.cancel()
            source = nil
            start()
        }
        pending?.cancel()
        pending = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
