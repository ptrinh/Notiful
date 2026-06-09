import Foundation
import NotifulCore

/// Watches the notification DB for changes. Primary mechanism is a DispatchSource on the `db-wal`
/// file (recent notifications are written there first). Falls back to / is backed up by an interval
/// timer. Both funnel into a debounced callback on the main queue.
final class Watcher {
    private let walURL: URL
    private let interval: TimeInterval
    private let onChange: () -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var timer: DispatchSourceTimer?
    private var debounceWork: DispatchWorkItem?

    init(databaseURL: URL, interval: TimeInterval, onChange: @escaping () -> Void) {
        self.walURL = databaseURL.deletingLastPathComponent()
            .appendingPathComponent(databaseURL.lastPathComponent + "-wal")
        self.interval = max(0.5, interval)
        self.onChange = onChange
    }

    func start() {
        armFileSource()
        startTimer()
    }

    func stop() {
        debounceWork?.cancel()
        timer?.cancel(); timer = nil
        teardownFileSource()
    }

    // MARK: - File source

    private func armFileSource() {
        teardownFileSource()
        fd = open(walURL.path, O_EVTONLY)
        guard fd >= 0 else {
            // WAL may not exist momentarily (after checkpoint). The timer will cover us; retry soon.
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .attrib],
            queue: .main)

        src.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = self.source?.data ?? []
            if flags.contains(.delete) || flags.contains(.rename) {
                // WAL was checkpointed/recreated — re-arm on the new file, then scan.
                self.armFileSource()
            }
            self.scheduleDebounced()
        }
        src.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fd >= 0 { close(self.fd); self.fd = -1 }
        }
        source = src
        src.resume()
    }

    private func teardownFileSource() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    // MARK: - Timer fallback

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: .main)
        // Generous leeway: this is only a fallback (kqueue handles real-time), so let the OS batch
        // these wakeups with other timers to save energy.
        t.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(5))
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            // If the file source died (WAL gone), try to re-arm.
            if self.fd < 0 { self.armFileSource() }
            self.scheduleDebounced()
        }
        timer = t
        t.resume()
    }

    // MARK: - Debounce

    private func scheduleDebounced() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
}
