import Foundation

/// An owned game with a Windows launch option, as known to the Mac Steam client.
public struct SteamGame: Identifiable, Hashable, Sendable {
    public let appID: UInt32
    public let name: String
    public let hasMacVersion: Bool
    public let installSize: Int64?
    let iconHash: String?

    public var id: UInt32 { appID }
}

public enum Artwork: Sendable {
    case hero, heroBlur, logo, capsule, header, icon

    /// Steam caches art per app, either at the top level or (newer clients) in hashed subfolders.
    public func url(for game: SteamGame) -> URL? {
        let dir = Paths.steamLibraryCache.appending(path: String(game.appID))
        let names: [String] = switch self {
        case .hero: ["library_hero.jpg"]
        case .heroBlur: ["library_hero_blur.jpg"]
        case .logo: ["logo.png"]
        case .capsule: ["library_600x900.jpg", "library_capsule.jpg"]
        case .header: ["header.jpg", "library_header.jpg"]
        case .icon: game.iconHash.map { ["\($0).jpg"] } ?? []
        }
        let fm = FileManager.default
        let subfolders = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath }
        for folder in [dir] + subfolders {
            for name in names where fm.fileExists(atPath: folder.appending(path: name).path) {
                return folder.appending(path: name)
            }
        }
        return nil
    }
}

public enum SteamLibrary {
    public static func games() throws -> [SteamGame] {
        let owned = try AppInfo.ownedAppIDs()
        return try AppInfo.all().compactMap { appID, info -> SteamGame? in
            let common = info["common"]
            guard owned.contains(appID),
                  common?["type"]?.text?.lowercased() == "game",
                  let launch = AppInfo.windowsLaunch(info),
                  let name = common?["name"]?.text
            else { return nil }
            let is64Bit = launch["config"]?["osarch"]?.text != "32"
            return SteamGame(appID: appID, name: name,
                             hasMacVersion: common?["oslist"]?.text?.contains("macos") ?? false,
                             installSize: AppInfo.windowsInstallSize(info, is64Bit: is64Bit),
                             iconHash: common?["icon"]?.text ?? common?["clienticon"]?.text)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func isInstalled(_ appID: UInt32, library: URL = Paths.library) -> Bool {
        (try? Library.game(appID: appID, library: library)) != nil
    }

    public static func sizeOnDisk(_ appID: UInt32, library: URL = Paths.library) -> Int64 {
        let dir = Library.directory(appID: appID, library: library)
        guard let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}
