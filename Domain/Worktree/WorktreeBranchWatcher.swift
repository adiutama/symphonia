import Foundation
import Darwin

/// Observes each checkout’s git `HEAD` file so UI can refresh branch labels after
/// `git checkout` / `git switch` without polling and **without writing** repo metadata.
///
/// Linked worktrees use a `.git` *file* (`gitdir: …`); we resolve that to the real HEAD path
/// under the main repo’s `worktrees/<name>/HEAD`.
@MainActor
final class WorktreeBranchWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private let queue = DispatchQueue(label: "symphonia.worktree-branch-watch")
    private var debounceWork: DispatchWorkItem?

    /// Fired on the main actor after HEAD changes (debounced).
    var onChange: (() -> Void)?

    deinit {
        // Cannot call MainActor cleanup from deinit reliably; cancel synchronously.
        for (_, source) in sources {
            source.cancel()
        }
        for (_, fd) in fileDescriptors where fd >= 0 {
            close(fd)
        }
    }

    /// Replace watched checkouts with this set (absolute worktree / main paths).
    func watch(checkouts: [URL]) {
        let wanted = Set(checkouts.map { $0.standardizedFileURL.path })
        for path in sources.keys where !wanted.contains(path) {
            stopWatching(path)
        }
        for checkout in checkouts {
            let path = checkout.standardizedFileURL.path
            if sources[path] == nil {
                startWatching(checkout: checkout.standardizedFileURL)
            }
        }
    }

    func stopAll() {
        for path in Array(sources.keys) {
            stopWatching(path)
        }
        debounceWork?.cancel()
        debounceWork = nil
    }

    // MARK: - Private

    private func startWatching(checkout: URL) {
        let key = checkout.path
        guard let headURL = Self.resolveHEADFile(in: checkout) else { return }
        let fd = open(headURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .link, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleEvent(forCheckoutPath: key)
            }
        }
        source.setCancelHandler {
            close(fd)
        }
        fileDescriptors[key] = fd
        sources[key] = source
        source.resume()
    }

    private func stopWatching(_ checkoutPath: String) {
        sources[checkoutPath]?.cancel()
        sources[checkoutPath] = nil
        fileDescriptors[checkoutPath] = nil
    }

    private func handleEvent(forCheckoutPath path: String) {
        // HEAD is often replaced on checkout — re-arm the watch after a short debounce.
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.stopWatching(path)
                self.startWatching(checkout: URL(fileURLWithPath: path))
                self.onChange?()
            }
        }
        debounceWork = work
        queue.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// Resolve `HEAD` for a checkout directory (plain repo or linked worktree).
    static func resolveHEADFile(in checkout: URL, fileManager: FileManager = .default) -> URL? {
        let gitPath = checkout.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: gitPath.path, isDirectory: &isDir) else {
            return nil
        }
        if isDir.boolValue {
            return gitPath.appendingPathComponent("HEAD")
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
            return gitDir.appendingPathComponent("HEAD")
        }
        return nil
    }
}
