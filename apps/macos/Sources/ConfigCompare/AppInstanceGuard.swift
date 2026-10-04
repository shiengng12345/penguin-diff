import AppKit
import Darwin
import Foundation

/// The packaged GUI owns one user-level lock. Keeping the policy pure lets the
/// fallback behavior be tested without opening a window or activating another
/// application.
enum AppInstancePolicy {
    static let productBundleIdentifier = "com.penguin.configcompare"

    static func shouldGuard(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == productBundleIdentifier
    }

    /// Used when the lock is unavailable, or to yield to an older unguarded
    /// copy. A newer peer must never make the current process exit: if two
    /// guarded launches race, the file lock decides the owner instead.
    static func existingPeer(
        currentProcessID: Int32,
        peerProcessIDs: [Int32],
        terminatedProcessIDs: [Int32] = []
    ) -> Int32? {
        let terminated = Set(terminatedProcessIDs)
        return peerProcessIDs
            .filter { $0 != currentProcessID && $0 < currentProcessID && !terminated.contains($0) }
            .min()
    }

    static func finishedPeer(
        currentProcessID: Int32,
        peerProcessIDs: [Int32],
        finishedProcessIDs: [Int32],
        terminatedProcessIDs: [Int32] = []
    ) -> Int32? {
        let finished = Set(finishedProcessIDs)
        let terminated = Set(terminatedProcessIDs)
        return peerProcessIDs
            .filter { $0 != currentProcessID && finished.contains($0) && !terminated.contains($0) }
            .min()
    }
}

fileprivate final class AppInstanceLock {
    enum Acquisition {
        case acquired(AppInstanceLock)
        case busy
        case unavailable
    }

    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(at url: URL) -> Acquisition {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return .unavailable
        }

        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { return .unavailable }
        var lock = Darwin.flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        guard Darwin.fcntl(descriptor, F_SETLK, &lock) == 0 else {
            let failure = Darwin.errno
            Darwin.close(descriptor)
            return failure == EWOULDBLOCK || failure == EAGAIN ? .busy : .unavailable
        }
        return .acquired(AppInstanceLock(descriptor: descriptor))
    }

    deinit {
        var lock = Darwin.flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_UNLCK), l_whence: Int16(SEEK_SET))
        _ = Darwin.fcntl(descriptor, F_SETLK, &lock)
        Darwin.close(descriptor)
    }
}

@MainActor
final class ConfigCompareAppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLock: AppInstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard AppInstancePolicy.shouldGuard(bundleIdentifier: Bundle.main.bundleIdentifier) else { return }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: AppInstancePolicy.productBundleIdentifier
        )
        let activePeers = applications.filter {
            $0.processIdentifier != currentProcessID && !$0.isTerminated
        }
        let finishedPeers = activePeers.filter(\.isFinishedLaunching)

        switch Self.acquireInstanceLock() {
        case .acquired(let lock):
            instanceLock = lock
            // A pre-guard copy may not hold this lock. Prefer only a process
            // that has completed launch; an unfinished peer may be another
            // contender which will lose the lock and exit itself.
            guard let peerProcessID = AppInstancePolicy.finishedPeer(
                currentProcessID: currentProcessID,
                peerProcessIDs: finishedPeers.map(\.processIdentifier),
                finishedProcessIDs: finishedPeers.map(\.processIdentifier)
            ), let existing = finishedPeers.first(where: { $0.processIdentifier == peerProcessID }) else {
                return
            }
            handOff(to: existing)
        case .busy:
            // The lock owner can be between process registration and the
            // running-apps snapshot. If a peer is visible, reuse it; if not,
            // terminate this contender so the lock owner can finish launch.
            guard let existing = finishedPeers.min(by: { $0.processIdentifier < $1.processIdentifier }) else {
                NSApp.terminate(nil)
                return
            }
            handOff(to: existing)
        case .unavailable:
            // Do not make a non-packaged/test invocation share the lock path.
            // If the user-level lock cannot be opened, retain the old-PID
            // fallback and fail open when no older GUI is visible.
            guard let peerProcessID = AppInstancePolicy.finishedPeer(
                currentProcessID: currentProcessID,
                peerProcessIDs: finishedPeers.map(\.processIdentifier),
                finishedProcessIDs: finishedPeers.map(\.processIdentifier)
            ), let existing = finishedPeers.first(where: { $0.processIdentifier == peerProcessID }) else {
                return
            }
            handOff(to: existing)
        }
    }

    private static func acquireInstanceLock() -> AppInstanceLock.Acquisition {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return .unavailable
        }
        let url = applicationSupport
            .appendingPathComponent("Config Compare", isDirectory: true)
            .appendingPathComponent("gui-instance.lock")
        return AppInstanceLock.acquire(at: url)
    }

    private func handOff(to existing: NSRunningApplication) {
        NSApp.yieldActivation(to: existing)
        if let bundleURL = existing.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            _ = existing.activate(options: [.activateAllWindows])
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
                Task { @MainActor in NSApp.terminate(nil) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                NSApp.terminate(nil)
            }
        } else {
            _ = existing.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }
}
