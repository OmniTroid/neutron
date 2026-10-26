import CryptoKit
import Foundation

public struct Config: Codable, Sendable {
    public var user: String?

    public static func load() -> Config {
        (try? JSONDecoder().decode(Config.self, from: Data(contentsOf: Paths.config))) ?? Config()
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: Paths.neutron, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Paths.config)
    }
}

public enum DepotDownloader {
    static let url = URL(string: "https://github.com/SteamRE/DepotDownloader/releases/download/DepotDownloader_3.4.0/DepotDownloader-macos-arm64.zip")!
    static let sha256 = "60e80c7c496f3f9a079cd3c62036b35d088c27bc0149baf38f009eb57a52f6a5"

    public static func ensure() async throws -> URL {
        let binary = Paths.depotDownloader
        if FileManager.default.fileExists(atPath: binary.path) { return binary }

        let (archive, _) = try await URLSession.shared.data(from: url)
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        guard digest == sha256 else { throw NeutronError("DepotDownloader checksum mismatch") }

        let dir = binary.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appending(path: "DepotDownloader.zip")
        try archive.write(to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, dir.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw NeutronError("failed to unpack DepotDownloader") }
        return binary
    }

    /// Downloads the Windows build of `game` with the terminal attached, so login prompts reach the user.
    public static func install(_ game: InstalledGame, user: String, library: URL = Paths.library) async throws {
        let binary = try await ensure()
        let dir = Library.directory(appID: game.appID, library: library)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = binary
        process.currentDirectoryURL = binary.deletingLastPathComponent()
        process.arguments = ["-app", String(game.appID), "-os", "windows", "-osarch", game.is64Bit ? "64" : "32",
                             "-dir", dir.path, "-username", user, "-remember-password", "-validate"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NeutronError("download of \(game.appID) failed") }
        try Library.save(game, library: library)
    }
}
