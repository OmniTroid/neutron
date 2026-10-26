import Foundation

public enum Runtime {
    /// The Wine runtime for `backend`: the base runtime itself for wined3d, otherwise the base with the
    /// backend's overlay applied, assembled once under Application Support (APFS clones, so no extra space).
    public static func url(for backend: Backend, dist: URL, cache: URL = Paths.runtimes) throws -> URL {
        let base = dist.appending(path: "wine")
        guard FileManager.default.fileExists(atPath: base.appending(path: "bin/wine").path) else {
            throw NeutronError("Wine runtime missing at \(base.path), run scripts/build.sh")
        }
        guard backend != .wined3d else { return base }
        let overlay = dist.appending(path: "overlays/\(backend.rawValue)")
        return try assemble(base: base, overlay: overlay, into: cache.appending(path: backend.rawValue))
    }

    static func assemble(base: URL, overlay: URL, into target: URL) throws -> URL {
        let fm = FileManager.default
        let stamp = try fingerprint(base: base, overlay: overlay)
        let stampURL = target.appending(path: ".neutron-runtime")
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp { return target }

        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        let bridge = base.appending(path: "lib/wine/x86_64-unix/lsteamclient.so")
        var lines = [base.path, describe(bridge)]
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
