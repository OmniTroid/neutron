import Foundation

public struct NeutronError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser

    public static let steam = home.appending(path: "Library/Application Support/Steam")
    public static let steamClient = steam.appending(path: "Steam.AppBundle/Steam/Contents/MacOS")
    public static let steamAppInfo = steam.appending(path: "appcache/appinfo.vdf")
    public static let steamPackageInfo = steam.appending(path: "appcache/packageinfo.vdf")
    public static let steamLibraryCache = steam.appending(path: "appcache/librarycache")

    public static let neutron = home.appending(path: "Library/Application Support/Neutron")
    public static let prefixes = neutron.appending(path: "prefixes")
    public static let library = neutron.appending(path: "library")
    public static let config = neutron.appending(path: "config.json")
    public static let depotDownloader = neutron.appending(path: "depotdownloader/DepotDownloader")

    /// Built runtimes: $NEUTRON_DIST, else the nearest `dist/` above the executable (a repo checkout).
    public static func dist() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["NEUTRON_DIST"] {
            return URL(filePath: override)
        }
        var dir = (Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0]))
            .resolvingSymlinksInPath().deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "dist")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "runtimes").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        throw NeutronError("runtimes not found, run scripts/build.sh or set NEUTRON_DIST")
    }
}
