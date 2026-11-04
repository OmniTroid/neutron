import Foundation

public enum Runtime {
    /// Files without which Wine would render with its own wined3d instead.
    static let dxmtFiles = ["d3d10core.dll", "d3d11.dll", "dxgi.dll", "winemetal.dll"]
        .flatMap { ["lib/wine/x86_64-windows/\($0)", "lib/wine/i386-windows/\($0)"] }
        + ["lib/wine/x86_64-windows/d3d12.dll", "lib/wine/x86_64-windows/d3d12core.dll", "lib/wine/x86_64-unix/winemetal.so"]

    /// The Wine runtime with DXMT applied, assembled once under Application Support (APFS clones, so no extra space).
    public static func url(dist: URL, cache: URL = Paths.runtimes) throws -> URL {
        let base = dist.appending(path: "wine")
        guard FileManager.default.fileExists(atPath: base.appending(path: "bin/wine").path) else {
            throw NeutronError("Wine runtime missing at \(base.path), run scripts/build.sh")
        }
        let overlay = dist.appending(path: "overlays/dxmt")
        let missing = dxmtFiles.filter { !FileManager.default.fileExists(atPath: overlay.appending(path: $0).path) }
        guard missing.isEmpty else {
            throw NeutronError("DXMT is incomplete in \(overlay.path) (missing \(missing.joined(separator: ", "))); Neutron only renders with DXMT, run scripts/build.sh")
        }
        return try assemble(base: base, overlay: overlay, into: cache.appending(path: "dxmt"))
    }

    static func assemble(base: URL, overlay: URL, into target: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // the app and the CLI, or two of the app's tasks, may ask at once: a second replacing the first's runtime
        // leaves it without the wine it was about to start
        let lock = open(target.deletingLastPathComponent().appending(path: ".assemble-lock").path, O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX) == 0 else { throw NeutronError("Couldn't lock the runtime to assemble it") }
        defer { close(lock) }
        let stamp = try fingerprint(base: base, overlay: overlay)
        let stampURL = target.appending(path: ".neutron-runtime")
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp,
           fm.fileExists(atPath: target.appending(path: "bin/wine").path) { return target }
        // replacing files under a running wineserver breaks every process it starts afterwards
        if fm.fileExists(atPath: target.appending(path: "bin/wine").path),
           WindowsSteam.processCommandLines().contains(where: { $0.contains(target.path + "/") }) { return target }

        let staging = target.deletingLastPathComponent().appending(path: ".\(target.lastPathComponent)-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: base, to: staging)
        for file in try files(in: overlay) {
            let destination = staging.appending(path: file)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.copyItem(at: overlay.appending(path: file), to: destination)
        }
        try stamp.write(to: staging.appending(path: ".neutron-runtime"), atomically: true, encoding: .utf8)

        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        return target
    }

    /// Changes whenever the bundled base or overlay changes, e.g. after an app update.
    static func fingerprint(base: URL, overlay: URL) throws -> String {
        var lines = [base.path]
        lines += try files(in: base).map { "\($0) \(describe(base.appending(path: $0)))" }
        lines += try files(in: overlay).map { "\($0) \(describe(overlay.appending(path: $0)))" }
        return lines.joined(separator: "\n")
    }

    static func describe(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return "\(values?.fileSize ?? -1) \(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }

    static func files(in dir: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        let root = dir.standardizedFileURL.path + "/"
        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL, (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return String(url.standardizedFileURL.path.dropFirst(root.count))
        }
        .sorted()
    }
}

@discardableResult
func run(_ executable: URL, _ arguments: [String], env: [String: String]) throws -> Int32 {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = env
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}
