// Writes scans into a folder, atomically and with unique names.
import Foundation

/// Folder-backed sink. Being an actor, name selection and the write happen in
/// one turn, so several printer sessions saving in the same second never
/// collide. `securityScoped` wraps each write in start/stop access for
/// folders picked with the document picker.
public actor FolderScanSink: ScanSink {
    public let directory: URL
    let securityScoped: Bool

    public init(directory: URL, securityScoped: Bool = false) {
        self.directory = directory
        self.securityScoped = securityScoped
    }

    public func write(_ data: Data, baseName: String, ext: String) async throws -> URL {
        let scoped = securityScoped && directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = FilenamePattern.unique(base: FilenamePattern.sanitize(baseName), ext: ext) {
            fm.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
        let target = directory.appendingPathComponent(name)
        Log.sink.debug("sink: writing \(target.lastPathComponent) bytes=\(data.count) scoped=\(scoped)")
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { url in
            do {
                // .atomic = temp file + rename in the same folder, so sync tools see one complete file.
                try data.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordError { throw coordError }
        if let writeError { throw writeError }
        Log.sink.info("sink: saved \(target.path) bytes=\(data.count)")
        return target
    }
}
