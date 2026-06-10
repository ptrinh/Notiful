import Foundation

/// Persists the last-processed record so the same code is never acted on twice across launches.
/// Stores only IDs/timestamps — NEVER the code itself.
public final class StateStore {
    public struct State: Codable, Equatable {
        public var lastRecID: Int64
        public var lastDeliveredDate: Double
        public init(lastRecID: Int64 = 0, lastDeliveredDate: Double = 0) {
            self.lastRecID = lastRecID
            self.lastDeliveredDate = lastDeliveredDate
        }
    }

    private let url: URL
    public private(set) var state: State

    public init(url: URL = ConfigStore.supportDirectory.appendingPathComponent("state.json")) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State()
        }
    }

    /// Has this record already been processed?
    public func isProcessed(recID: Int64) -> Bool {
        recID <= state.lastRecID
    }

    /// Advance the watermark to this record (only moves forward) and persist immediately.
    public func markProcessed(recID: Int64, deliveredDate: Double) {
        advance(recID: recID, deliveredDate: deliveredDate)
        flush()
    }

    /// Advance the watermark WITHOUT writing to disk — call `flush()` once after a batch.
    public func advance(recID: Int64, deliveredDate: Double) {
        if recID > state.lastRecID {
            state.lastRecID = recID
            state.lastDeliveredDate = deliveredDate
            dirty = true
        }
    }

    /// Write the state to disk if it changed since the last persist.
    public func flush() {
        guard dirty else { return }
        persist()
        dirty = false
    }

    private var dirty = false

    private func persist() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url)
        }
    }
}
