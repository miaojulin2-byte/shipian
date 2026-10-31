import AppKit

/// A file must keep the same size and modification time for two scans.
/// Existing files are baselined, so enabling capture does not import the Desktop.
final class ImageFolderWatcher {
    private let folders: [URL]
    private var known = Set<URL>()
    private var pending: [URL: String] = [:]
    init(folders: [URL]) {
        self.folders = folders
        known = Set(files().keys)
    }
    private func files() -> [URL: String] {
        var result: [URL: String] = [:]
        for folder in folders {
            for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])) ?? [] {
                guard ["png", "jpg", "jpeg", "tiff", "heic"].contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]), values.isRegularFile == true else { continue }
                result[url] = "\(values.fileSize ?? 0):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
            }
        }
        return result
    }
    func newImages() -> [URL] {
        let current = files()
        known = known.intersection(Set(current.keys))
        var ready: [URL] = []
        for (url, signature) in current where !known.contains(url) {
            if pending[url] == signature { ready.append(url); known.insert(url); pending[url] = nil }
            else { pending[url] = signature }
        }
        pending = pending.filter { current[$0.key] != nil }
        return ready.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func retry(_ url: URL) { known.remove(url) }
}

@MainActor final class ScreenshotInbox {
    let folder: URL
    private let notes: Notes
    private var watcher: ImageFolderWatcher!
    private var lastScan = Date.distantPast
    private let domain: String
    private let settings: UserDefaults
    private let savedKey = "originalScreenshotSettings"
    private let appliedKey = "appliedScreenshotSettings"
    private var preferences: UserDefaults { UserDefaults(suiteName: domain)! }
    private(set) var enabled = false
    init(notes: Notes, domain: String = "com.apple.screencapture", settings: UserDefaults = .standard, folder: URL? = nil) {
        self.notes = notes
        self.domain = domain
        self.settings = settings
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Textline/Screenshots")
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        watcher = ImageFolderWatcher(folders: [self.folder])
        if !settings.bool(forKey: "screenshotsDisabled") { enable() }
    }
    private func write(_ key: String, _ value: Any?) {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        if let value {
            if let number = value as? NSNumber { process.arguments = ["write", domain, key, "-bool", number.boolValue ? "true" : "false"] }
            else { process.arguments = ["write", domain, key, "-string", "\(value)"] }
        } else { process.arguments = ["delete", domain, key] }
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() }
        catch { notes.storageError = "无法更新截图位置：\(error.localizedDescription)" }
    }
    private func enable() {
        let applied: [String: Any] = ["location": folder.path, "location-screenshot": folder.path, "target": "file", "target-screenshot": "file", "show-thumbnail": false]
        if settings.dictionary(forKey: savedKey) == nil {
            let original = preferences.persistentDomain(forName: domain) ?? [:]
            var saved: [String: Any] = [:]
            for key in applied.keys { saved[key] = ["exists": original[key] != nil, "value": original[key] ?? ""] }
            settings.set(saved, forKey: savedKey)
        }
        settings.set(applied, forKey: appliedKey)
        settings.synchronize()
        for (key, value) in applied { write(key, value) }
        enabled = true
    }
    func restoreSettings() {
        guard let saved = settings.dictionary(forKey: savedKey), let applied = settings.dictionary(forKey: appliedKey) else { return }
        preferences.synchronize()
        let current = preferences.persistentDomain(forName: domain) ?? [:]
        for (key, value) in applied {
            guard let now = current[key] as? NSObject, now.isEqual(value), let original = saved[key] as? [String: Any] else { continue }
            write(key, original["exists"] as? Bool == true ? original["value"] : nil)
        }
        settings.removeObject(forKey: savedKey)
        settings.removeObject(forKey: appliedKey)
        enabled = false
    }
    func toggle() {
        if enabled { restoreSettings() } else { enable() }
        settings.set(!enabled, forKey: "screenshotsDisabled")
    }
    func tick() {
        guard Date().timeIntervalSince(lastScan) > 0.6 else { return }
        lastScan = Date()
        guard !notes.paused else { return }
        for url in watcher.newImages() {
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= 32 * 1024 * 1024 else { continue }
            if let data = try? Data(contentsOf: url), notes.hangImage(data) {
                // Captured files belong to our inbox; the persisted PNG is now authoritative.
                try? FileManager.default.removeItem(at: url)
            } else { watcher.retry(url) }
        }
    }
}
