import Foundation
import CoreServices

/// Recursive native notifications also cover new sessions and atomic hook snapshots.
@MainActor final class AgentFileWatcher {
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private var lastDelivery = Date.distantPast
    private var changed: (() -> Void)?
    private var roots: [String] = []
    func start(home: URL = FileManager.default.homeDirectoryForCurrentUser, changed: @escaping () -> Void) {
        stop()
        self.changed = changed
        roots = [home.appending(path: ".codex/sessions").path, home.appending(path: ".claude/projects").path,
                 ClaudeBridge.folder.path, ClaudeActivity.folder.path, ClaudeDesktopLimits.file.path].map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        // Watch existing ancestors so first installation/new directories are detected too.
        let paths = Set(roots.map { root -> String in
            var url = URL(fileURLWithPath: root)
            while !FileManager.default.fileExists(atPath: url.path), url.path != "/" { url.deleteLastPathComponent() }
            return url.path
        })
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<AgentFileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
            MainActor.assumeIsolated { watcher.receive(Array(paths.prefix(count))) }
        }
        stream = FSEventStreamCreate(nil, callback, &context, Array(paths) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
                                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) { stop() }
        }
    }
    private func receive(_ paths: [String]) {
        guard paths.contains(where: { raw in
            let path = URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
            return roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") })
        }) else { return }
        // Schedule once; continuous writes must not postpone updates indefinitely.
        guard pending == nil else { return }
        let delay = max(0.2, 2 - Date().timeIntervalSince(lastDelivery))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil; self.lastDelivery = Date(); self.changed?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func stop() {
        pending?.cancel(); pending = nil; changed = nil
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
    }
}
