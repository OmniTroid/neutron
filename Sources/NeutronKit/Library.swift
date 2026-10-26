import Foundation

/// What `install` records about a game; everything `run` needs to launch it.
public struct InstalledGame: Codable, Equatable, Sendable {
    public var appID: UInt32
    public var name: String
    public var executable: String
    public var arguments: String
    public var workingDirectory: String?
    public var is64Bit: Bool

    public init?(appID: UInt32, appInfo: KeyValue) {
        guard let launch = AppInfo.windowsLaunch(appInfo), let executable = launch["executable"]?.text else { return nil }
        self.appID = appID
        self.name = appInfo["common"]?["name"]?.text ?? String(appID)
        self.executable = executable
        self.arguments = launch["arguments"]?.text ?? ""
        self.workingDirectory = launch["workingdir"]?.text
        self.is64Bit = launch["config"]?["osarch"]?.text != "32"
    }
}

public enum Library {
    public static func directory(appID: UInt32, library: URL = Paths.library) -> URL {
        library.appending(path: String(appID))
    }

    static func manifest(appID: UInt32, library: URL) -> URL {
        directory(appID: appID, library: library).appending(path: "neutron.json")
    }

    public static func game(appID: UInt32, library: URL = Paths.library) throws -> InstalledGame {
        let url = manifest(appID: appID, library: library)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NeutronError("\(appID) is not installed, run `neutron install \(appID)`")
        }
        return try JSONDecoder().decode(InstalledGame.self, from: Data(contentsOf: url))
    }

    public static func save(_ game: InstalledGame, library: URL = Paths.library) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(game).write(to: manifest(appID: game.appID, library: library))
    }

    /// Absolute exe, working directory and arguments, with Windows separators converted.
    public static func launch(_ game: InstalledGame, library: URL = Paths.library) -> (exe: URL, workingDirectory: URL, arguments: [String]) {
        let root = directory(appID: game.appID, library: library)
        let exe = root.appending(path: game.executable.replacingOccurrences(of: "\\", with: "/"))
        let workingDirectory = game.workingDirectory.map {
            root.appending(path: $0.replacingOccurrences(of: "\\", with: "/"))
        } ?? exe.deletingLastPathComponent()
        return (exe, workingDirectory, splitArguments(game.arguments))
    }

    /// Splits a launch argument string on whitespace, honoring double quotes.
    public static func splitArguments(_ string: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var pending = false
        for char in string {
            if char == "\"" {
                quoted.toggle()
                pending = true
            } else if char.isWhitespace && !quoted {
                if pending { result.append(current) }
                current = ""
                pending = false
            } else {
                current.append(char)
                pending = true
            }
        }
        if pending { result.append(current) }
        return result
    }
}
