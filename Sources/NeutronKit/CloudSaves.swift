import Foundation

/// A Windows save folder inside a prefix that should be the macOS folder Mac Steam's Auto-Cloud syncs.
public struct SaveLink: Equatable, Sendable {
    public var windowsRoot: String
    public var windowsPath: String
    public var macRoot: String
    public var macPath: String
}

public enum CloudSaves {
    static let windowsRoots = [
        "WinMyDocuments": "Documents",
        "WinAppDataLocal": "AppData/Local",
        "WinAppDataLocalLow": "AppData/LocalLow",
        "WinAppDataRoaming": "AppData/Roaming",
        "WinSavedGames": "Saved Games",
    ]
    static let macRoots = [
        "MacAppSupport": "Library/Application Support",
        "MacDocuments": "Documents",
        "MacHome": "",
        "MacCaches": "Library/Caches",
    ]

    /// Pairs each Windows Auto-Cloud rule with where Mac Steam syncs the same files.
    public static func links(for appInfo: KeyValue) -> [SaveLink] {
        let ufs = appInfo["ufs"]
        let rules = (ufs?["savefiles"]?.children ?? []).map(\.value)

        func platforms(_ rule: KeyValue) -> [String] {
            (rule["platforms"]?.children ?? []).compactMap { $0.value.text?.lowercased() }
        }
        func usable(_ path: String) -> Bool { !path.contains("{") }

        var result: [SaveLink] = []
        for rule in rules {
            let rulePlatforms = platforms(rule)
            guard rulePlatforms.isEmpty || rulePlatforms.contains("windows"),
                  let root = rule["root"]?.text, windowsRoots[root] != nil,
                  let path = rule["path"]?.text, usable(path) else { continue }
            let pattern = rule["pattern"]?.text

            let macRule = rules.first {
                platforms($0).contains("macos") && $0["pattern"]?.text == pattern
                    && macRoots[$0["root"]?.text ?? ""] != nil && usable($0["path"]?.text ?? "{")
            }
            if let macRule, let macRoot = macRule["root"]?.text, let macPath = macRule["path"]?.text {
                result.append(SaveLink(windowsRoot: root, windowsPath: path, macRoot: macRoot, macPath: macPath))
                continue
            }

            guard rulePlatforms.isEmpty else { continue }
            let override = (ufs?["rootoverrides"]?.children ?? []).map(\.value).first {
                $0["root"]?.text == root && $0["os"]?.text?.lowercased() == "macos"
            }
            if let override, let macRoot = override["useinstead"]?.text, macRoots[macRoot] != nil {
                let addPath = override["addpath"]?.text ?? ""
                let macPath = [addPath, path].filter { !$0.isEmpty }.joined(separator: "/")
                result.append(SaveLink(windowsRoot: root, windowsPath: path, macRoot: macRoot, macPath: macPath))
            }
        }
        return result
    }

    /// Creates the links in `prefix`; returns notes about rules it skipped to avoid touching existing saves.
    public static func apply(_ links: [SaveLink], prefix: URL, home: URL = Paths.home, user: String = NSUserName()) throws -> [String] {
        let fm = FileManager.default
        var notes: [String] = []
        for link in links {
            guard let winBase = windowsRoots[link.windowsRoot], let macBase = macRoots[link.macRoot] else { continue }
            let windowsDir = prefix.appending(path: "drive_c/users/\(user)/\(winBase)/\(normalize(link.windowsPath))")
            let macDir = home.appending(path: "\(macBase)/\(normalize(link.macPath))")
            try fm.createDirectory(at: macDir, withIntermediateDirectories: true)

            if let target = try? fm.destinationOfSymbolicLink(atPath: windowsDir.path) {
                if URL(filePath: target).standardizedFileURL == macDir.standardizedFileURL { continue }
                try fm.removeItem(at: windowsDir)
            } else if fm.fileExists(atPath: windowsDir.path) {
                guard (try fm.contentsOfDirectory(atPath: windowsDir.path)).isEmpty else {
                    notes.append("kept existing saves in \(windowsDir.path); not linked to \(macDir.path)")
                    continue
                }
                try fm.removeItem(at: windowsDir)
            }
            try fm.createDirectory(at: windowsDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: windowsDir, withDestinationURL: macDir)
        }
        return notes
    }

    static func normalize(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension Prefix {
    /// Links this app's Auto-Cloud save folders before launch; returns notes about skipped rules.
    public func linkCloudSaves(appID: UInt32) throws -> [String] {
        guard let appInfo = try AppInfo.read(appID: appID) else { return [] }
        return try CloudSaves.apply(CloudSaves.links(for: appInfo), prefix: url)
    }
}
