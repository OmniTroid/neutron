import Foundation

public struct NeutronError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let neutron = home.appending(path: "Library/Application Support/Neutron")
    public static let runtimes = neutron.appending(path: "runtimes")
    /// The Wine prefix holding Valve's Windows Steam client.
    public static let steamPrefix = neutron.appending(path: "steam")
    public static let steam = steamPrefix.appending(path: "drive_c/Program Files (x86)/Steam")
    public static let steamAppInfo = steam.appending(path: "appcache/appinfo.vdf")
    public static let steamPackageInfo = steam.appending(path: "appcache/packageinfo.vdf")
    public static let steamLibraryCache = steam.appending(path: "appcache/librarycache")

    /// Built runtimes: $NEUTRON_DIST, else the app bundle's SharedSupport/dist, else the nearest `dist/`
    /// above the executable (a repo checkout).
    public static func dist() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["NEUTRON_DIST"] {
            return URL(filePath: override)
        }
        guard let dist = shared("dist", containing: "wine/bin/wine") else {
            throw NeutronError("runtimes not found, run scripts/build.sh or set NEUTRON_DIST")
        }
        return dist
    }

    /// Bundled data such as compat.json, found the same way as `dist()`.
    public static func data() -> URL? {
        shared("data", containing: "compat.json")
    }

    static func shared(_ name: String, containing marker: String) -> URL? {
        var dir = (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath().deletingLastPathComponent()
        while dir.path != "/" {
            for candidate in [dir.appending(path: "SharedSupport/\(name)"), dir.appending(path: name)]
            where FileManager.default.fileExists(atPath: candidate.appending(path: marker).path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }
}
