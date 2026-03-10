import Foundation

/// Poll-based monitor that tails the shared activity event log from managed agent wrappers.
final class AgentCompletionEventMonitor: AgentActivityEventMonitoring {
    var onEvent: ((AgentActivityEvent) -> Void)?

    private let logURL: URL
    private let queue = DispatchQueue(label: "com.shellraiser.completion-event-monitor")
    private let compactionThresholdBytes: UInt64 = 64 * 1024
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var readOffset: UInt64 = 0
    private var trailingFragment = ""

    /// Creates a monitor for the provided event log and starts tailing new events.
    init(logURL: URL) {
        self.logURL = logURL
        start()
    }

    deinit {
        source?.cancel()
        closeDescriptorIfNeeded()
    }

    /// Starts watching the activity log from the current end of file so historical events are ignored.
    private func start() {
        rebuildWatchSource(seekToEnd: true)
    }

    /// Rebuilds the file watcher, optionally seeking to the end to skip historical events.
    private func rebuildWatchSource(seekToEnd: Bool) {
        source?.cancel()
        source = nil
        closeDescriptorIfNeeded()

        fileDescriptor = open(logURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        if seekToEnd,
           let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attributes[.size] as? NSNumber {
            readOffset = size.uint64Value
        } else {
            readOffset = min(readOffset, currentFileSize())
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleFileSystemEvent()
        }
        source.setCancelHandler { [weak self] in
            self?.closeDescriptorIfNeeded()
        }

        self.source = source
        source.resume()
    }

    /// Handles filesystem changes and consumes any newly appended activity events.
    private func handleFileSystemEvent() {
        let flags = source?.data ?? []

        if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
            rebuildWatchSource(seekToEnd: false)
            consumePendingEvents()
            return
        }

        consumePendingEvents()
    }

    /// Reads newly appended log data and emits parsed activity events on the main actor.
    private func consumePendingEvents() {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer {
            try? handle.close()
        }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        if fileSize < readOffset {
            readOffset = 0
            trailingFragment = ""
        }

        guard fileSize > readOffset else { return }

        try? handle.seek(toOffset: readOffset)
        let data = handle.readDataToEndOfFile()
        readOffset = fileSize

        guard !data.isEmpty else { return }

        let chunk = trailingFragment + String(decoding: data, as: UTF8.self)
        let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false)

        trailingFragment = lines.last.map(String.init) ?? ""

        let completeLines = chunk.hasSuffix("\n")
            ? lines.map(String.init)
            : lines.dropLast().map(String.init)

        for line in completeLines where !line.isEmpty {
            guard let event = AgentActivityEvent.parse(line) else { continue }
            CompletionDebugLogger.log(
                "event runtime=\(event.agentType.rawValue) phase=\(event.phase.rawValue) surface=\(event.surfaceId.uuidString)"
            )
            Task { @MainActor in
                self.onEvent?(event)
            }
        }

        if chunk.hasSuffix("\n") {
            trailingFragment = ""
        }

        compactLogIfNeeded(fileSize: fileSize)
    }

    /// Truncates the event log once all bytes have been consumed and the file grows past the threshold.
    private func compactLogIfNeeded(fileSize: UInt64) {
        guard trailingFragment.isEmpty else { return }
        guard readOffset == fileSize else { return }
        guard fileSize >= compactionThresholdBytes else { return }

        do {
            try FileHandle(forWritingTo: logURL).truncate(atOffset: 0)
            readOffset = 0
            CompletionDebugLogger.log("compacted completion log bytes=\(fileSize)")
        } catch {
            CompletionDebugLogger.log("failed to compact completion log: \(error)")
        }
    }

    /// Returns the current file size for the watched completion log.
    private func currentFileSize() -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }

        return size.uint64Value
    }

    /// Closes the watched file descriptor if it is currently open.
    private func closeDescriptorIfNeeded() {
        guard fileDescriptor >= 0 else { return }
        Darwin.close(fileDescriptor)
        fileDescriptor = -1
    }
}
