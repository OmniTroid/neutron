import CryptoKit
import Foundation

public struct Config: Codable, Sendable {
    public var user: String?
    public var backends: [String: String]?

    public func backend(for appID: UInt32) -> Backend {
        backends?[String(appID)].flatMap(Backend.init(rawValue:)) ?? .dxmt
    }

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

public enum InstallPrompt: Sendable, Equatable {
    case password
    case guardCode
    case emailCode(String)
    case mobileConfirmation
}

public enum InstallEvent: Sendable {
    case status(String)
    case progress(Double)
    case prompt(InstallPrompt)
    case finished(Result<Void, NeutronError>)
}

/// A DepotDownloader run driven through pipes, for the app: reports progress and login prompts.
public final class InstallSession: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var buffer = ""
    private var lastLine = ""
    private var cancelled = false

    public init(game: InstalledGame, user: String, library: URL = Paths.library,
                onEvent: @escaping @Sendable (InstallEvent) -> Void) async throws {
        let binary = try await DepotDownloader.ensure()
        let dir = Library.directory(appID: game.appID, library: library)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        process.executableURL = binary
        process.currentDirectoryURL = binary.deletingLastPathComponent()
        process.arguments = ["-app", String(game.appID), "-os", "windows", "-osarch", game.is64Bit ? "64" : "32",
                             "-dir", dir.path, "-username", user, "-remember-password", "-validate"]
        // DepotDownloader requires distinct login IDs when instances overlap, e.g. a CLI download
        process.arguments! += ["-loginid", String(UInt32.random(in: 1...UInt32.max))]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            for event in self.consume(String(decoding: data, as: UTF8.self)) { onEvent(event) }
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            self.output.fileHandleForReading.readabilityHandler = nil
            let (cancelled, lastLine) = self.lock.withLock { (self.cancelled, self.lastLine) }
            if cancelled {
                onEvent(.finished(.failure(NeutronError("Download cancelled"))))
            } else if process.terminationStatus == 0 {
                do {
                    try Library.save(game, library: library)
                    onEvent(.finished(.success(())))
                } catch {
                    onEvent(.finished(.failure(NeutronError("\(error)"))))
                }
            } else {
                onEvent(.finished(.failure(NeutronError(lastLine.isEmpty ? "Download failed" : lastLine))))
            }
        }
        try process.run()
    }

    public func respond(_ text: String) {
        input.fileHandleForWriting.write(Data((text + "\n").utf8))
    }

    public func cancel() {
        lock.withLock { cancelled = true }
        process.terminate()
    }

    private func consume(_ chunk: String) -> [InstallEvent] {
        lock.withLock {
            buffer += chunk
            var events: [InstallEvent] = []
            while let end = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
                let line = buffer[..<end].trimmingCharacters(in: .whitespaces)
                buffer.removeSubrange(...end)
                guard !line.isEmpty else { continue }
                lastLine = line
                events.append(contentsOf: InstallSession.parse(line: line))
            }
            // prompts are written without a trailing newline
            if let prompt = InstallSession.prompt(in: buffer) {
                buffer = ""
                events.append(.prompt(prompt))
            }
            return events
        }
    }

    static func parse(line: String) -> [InstallEvent] {
        if line.contains("Use the Steam Mobile App to confirm") { return [.prompt(.mobileConfirmation)] }
        if let percent = line.firstMatch(of: /^(\d+(?:\.\d+)?)% (.+)$/) {
            let file = String(percent.2).split(separator: "/").last.map(String.init) ?? ""
            return [.progress((Double(percent.1) ?? 0) / 100), .status(file)]
        }
        if line.hasPrefix("Logging") || line.hasPrefix("Connecting") { return [.status("Signing in to Steam…")] }
        if line.hasPrefix("Downloading depot") || line.hasPrefix("Processing depot") { return [.status("Preparing download…")] }
        if line.hasPrefix("Validating") { return [.status("Validating files…")] }
        return []
    }

    static func prompt(in pending: String) -> InstallPrompt? {
        if pending.contains("Enter account password") { return .password }
        if pending.contains("2-factor auth code from your authenticator") { return .guardCode }
        if let match = pending.firstMatch(of: /auth code sent to the email at (.+?):/) { return .emailCode(String(match.1)) }
        return nil
    }
}
