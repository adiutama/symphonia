import Darwin
import Foundation

/// Inserted / deleted line counts for Glance Changes (ADR 0023).
struct GitDiffStats: Equatable, Sendable {
    var inserted: Int
    var deleted: Int

    static let zero = GitDiffStats(inserted: 0, deleted: 0)
}

/// Best-effort git diff stats for a checkout directory.
enum GitDiffStatsReader: Sendable {
    static func read(from directory: URL) -> GitDiffStats? {
        guard isGitRepository(directory) else { return nil }

        var inserted = 0
        var deleted = 0

        if let numstat = try? runGit(["diff", "--numstat", "HEAD"], in: directory) {
            for line in numstat.split(separator: "\n", omittingEmptySubsequences: true) {
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard parts.count >= 2 else { continue }
                if parts[0] != "-", let add = Int(parts[0]) { inserted += add }
                if parts[1] != "-", let sub = Int(parts[1]) { deleted += sub }
            }
        }

        if let untracked = try? runGit(
            ["ls-files", "--others", "--exclude-standard"],
            in: directory
        ) {
            for line in untracked.split(separator: "\n", omittingEmptySubsequences: true) {
                let relative = String(line)
                let fileURL = directory.appendingPathComponent(relative)
                inserted += lineCount(at: fileURL)
            }
        }

        return GitDiffStats(inserted: inserted, deleted: deleted)
    }

    private static func isGitRepository(_ directory: URL) -> Bool {
        guard let output = try? runGit(["rev-parse", "--is-inside-work-tree"], in: directory) else {
            return false
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private static func lineCount(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return 0 }
        if text.isEmpty { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "GitDiffStats", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: err.isEmpty ? "git exit \(process.terminationStatus)" : err,
            ])
        }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Resolve `index` for a checkout (plain repo or linked worktree).
    static func resolveIndexFile(in checkout: URL, fileManager: FileManager = .default) -> URL? {
        let gitPath = checkout.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: gitPath.path, isDirectory: &isDir) else {
            return nil
        }
        if isDir.boolValue {
            return gitPath.appendingPathComponent("index")
        }
        guard let raw = try? String(contentsOf: gitPath, encoding: .utf8) else {
            return nil
        }
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("gitdir:") else { continue }
            let rest = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rest.isEmpty else { continue }
            let gitDir: URL
            if rest.hasPrefix("/") {
                gitDir = URL(fileURLWithPath: rest, isDirectory: true)
            } else {
                gitDir = URL(fileURLWithPath: rest, relativeTo: checkout).standardizedFileURL
            }
            return gitDir.appendingPathComponent("index")
        }
        return nil
    }
}

/// Live Glance Changes: FSEvents on the checkout + git index watch + light poll while active.
@MainActor
final class GitDiffStatsMonitor: ObservableObject {
    @Published private(set) var stats: GitDiffStats = .zero

    private var directory: URL?
    private var refreshTask: Task<Void, Never>?
    private var debounceWork: DispatchWorkItem?
    private var pollTimer: Timer?
    private var indexSource: DispatchSourceFileSystemObject?
    private var indexFD: Int32 = -1
    private var eventStream: FSEventStreamRef?
    private let watchQueue = DispatchQueue(label: "symphonia.git-diff-watch")

    deinit {
        // Best-effort sync teardown (MainActor deinit is not guaranteed).
        pollTimer?.invalidate()
        indexSource?.cancel()
        if indexFD >= 0 { close(indexFD) }
        if let eventStream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
        }
    }

    /// Begin monitoring a checkout. No-op if already watching the same path.
    func start(directory: URL) {
        let standardized = directory.standardizedFileURL
        if self.directory?.path == standardized.path, pollTimer != nil {
            scheduleRefresh(immediate: true)
            return
        }
        stop()
        self.directory = standardized
        startIndexWatch(checkout: standardized)
        startFSEvents(checkout: standardized)
        startPolling()
        scheduleRefresh(immediate: true)
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        debounceWork?.cancel()
        debounceWork = nil
        pollTimer?.invalidate()
        pollTimer = nil
        stopIndexWatch()
        stopFSEvents()
        directory = nil
    }

    // MARK: - Refresh

    private func scheduleRefresh(immediate: Bool) {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
        debounceWork = work
        let delay = immediate ? 0.0 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshNow() {
        guard let directory else {
            stats = .zero
            return
        }
        refreshTask?.cancel()
        let dir = directory
        refreshTask = Task {
            let next = await Task.detached(priority: .utility) {
                GitDiffStatsReader.read(from: dir) ?? .zero
            }.value
            guard !Task.isCancelled else { return }
            if stats != next {
                stats = next
            }
        }
    }

    // MARK: - Poll (backup for editors that write without FSEvents coalescing)

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleRefresh(immediate: true)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    // MARK: - Index file

    private func startIndexWatch(checkout: URL) {
        stopIndexWatch()
        guard let indexURL = GitDiffStatsReader.resolveIndexFile(in: checkout) else { return }
        let fd = open(indexURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        indexFD = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .link, .revoke],
            queue: watchQueue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleIndexEvent(checkout: checkout)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        indexSource = source
        source.resume()
    }

    private func handleIndexEvent(checkout: URL) {
        // Index is often replaced atomically — re-arm watch.
        stopIndexWatch()
        startIndexWatch(checkout: checkout)
        scheduleRefresh(immediate: false)
    }

    private func stopIndexWatch() {
        indexSource?.cancel()
        indexSource = nil
        indexFD = -1
    }

    // MARK: - FSEvents (working tree)

    private func startFSEvents(checkout: URL) {
        stopFSEvents()
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = [checkout.path as CFString] as CFArray
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            nil,
            gitDiffFSEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.4,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, watchQueue)
        FSEventStreamStart(stream)
        eventStream = stream
    }

    private func stopFSEvents() {
        guard let eventStream else { return }
        FSEventStreamStop(eventStream)
        FSEventStreamInvalidate(eventStream)
        FSEventStreamRelease(eventStream)
        self.eventStream = nil
    }

    nonisolated func handleFSEvents(paths: [String]) {
        // Ignore noisy .git internals except we already watch index separately;
        // still refresh — cheap enough with debounce.
        let relevant = paths.contains { path in
            let lower = path.lowercased()
            if lower.contains("/.git/") {
                // Index / HEAD / refs still mean stats may change.
                return lower.hasSuffix("/index")
                    || lower.hasSuffix("/head")
                    || lower.contains("/refs/")
                    || lower.contains("/objects/")
            }
            return true
        }
        guard relevant else { return }
        Task { @MainActor in
            self.scheduleRefresh(immediate: false)
        }
    }
}

private func gitDiffFSEventsCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let monitor = Unmanaged<GitDiffStatsMonitor>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
    _ = eventFlags
    _ = eventIds
    _ = numEvents
    _ = streamRef
    monitor.handleFSEvents(paths: paths)
}
