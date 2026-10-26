import Foundation

public enum Backend: String, CaseIterable, Sendable {
    case dxmt
    case wined3d
}

public struct Command: Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]
    public var workingDirectory: URL?
}

public struct Prefix: Sendable {
    public let url: URL
    public let backend: Backend
    let runtime: URL
    let dist: URL

    static let steamReg = #"""
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\Software\Valve\Steam]
        "SteamPath"="C:\\Program Files (x86)\\Steam"
        "SteamExe"="C:\\Program Files (x86)\\Steam\\steam.exe"

        [HKEY_CURRENT_USER\Software\Valve\Steam\ActiveProcess]
        "SteamClientDll"="C:\\Program Files (x86)\\Steam\\steamclient.dll"
        "SteamClientDll64"="C:\\Program Files (x86)\\Steam\\steamclient64.dll"
        "SteamPath"="C:\\Program Files (x86)\\Steam"

        [HKEY_LOCAL_MACHINE\Software\Wow6432Node\Valve\Steam]
        "InstallPath"="C:\\Program Files (x86)\\Steam"

        """#

    public init(url: URL, backend: Backend) throws {
        self.url = url
        self.backend = backend
        dist = try Paths.dist()
        runtime = try Runtime.url(for: backend, dist: dist)
    }

    public static func forApp(_ appID: UInt32?, backend: Backend) throws -> Prefix {
        try Prefix(url: Paths.prefixes.appending(path: appID.map(String.init) ?? "default"), backend: backend)
    }

    var wine: URL { runtime.appending(path: "bin/wine") }

    public func environment(appID: UInt32?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = url.path
        env["WINEDEBUG"] = env["WINEDEBUG"] ?? "-all"
        env["STEAM_COMPAT_CLIENT_INSTALL_PATH"] = Paths.steamClient.path
        if let appID {
            env["SteamAppId"] = String(appID)
            env["SteamGameId"] = String(appID)
        }
        return env
    }

    /// Creates or updates the prefix when the runtime or backend changed since last setup.
    public func prepare() throws {
        let fm = FileManager.default
        let stampURL = url.appending(path: ".neutron")
        let bridge = runtime.appending(path: "lib/wine/x86_64-unix/lsteamclient.so")
        let mtime = (try fm.attributesOfItem(atPath: bridge.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let stamp = "\(backend.rawValue)\n\(mtime)"
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp { return }

        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        let env = environment(appID: nil)
        // exits nonzero on harmless setupapi warnings
        _ = try run(wine, ["wineboot", "-u"], env: env)
        guard fm.fileExists(atPath: url.appending(path: "drive_c/windows/system32/lsteamclient.dll").path) else {
            throw NeutronError("wineboot failed to set up \(url.path)")
        }

        let steamDir = url.appending(path: "drive_c/Program Files (x86)/Steam")
        try fm.createDirectory(at: steamDir, withIntermediateDirectories: true)
        for name in ["steamclient.dll", "steamclient64.dll"] {
            let target = steamDir.appending(path: name)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: dist.appending(path: "steam/\(name)"), to: target)
        }

        let reg = url.appending(path: "neutron-steam.reg")
        try Prefix.steamReg.write(to: reg, atomically: true, encoding: .utf8)
        guard try run(wine, ["regedit", "/S", reg.path], env: env) == 0 else {
            throw NeutronError("failed to import Steam registry keys")
        }
        _ = try run(runtime.appending(path: "bin/wineserver"), ["-w"], env: env)
        try stamp.write(to: stampURL, atomically: true, encoding: .utf8)
    }

    /// Launch through Proton's steam.exe, which sets up the Steam environment and waits for the game.
    public func gameCommand(appID: UInt32?, exe: URL, workingDirectory: URL, arguments: [String]) -> Command {
        // an explicit path makes wine load steam.exe directly; via start.exe its wait for all processes deadlocks
        Command(executable: wine,
                arguments: [#"C:\windows\system32\steam.exe"#, "Z:" + exe.path.replacingOccurrences(of: "/", with: "\\")] + arguments,
                environment: environment(appID: appID),
                workingDirectory: workingDirectory)
    }

    public func wineCommand(_ arguments: [String]) -> Command {
        Command(executable: wine, arguments: arguments, environment: environment(appID: nil), workingDirectory: nil)
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

/// A running game, launched for the app; output goes to `neutron.log` in the prefix.
public final class GameSession: @unchecked Sendable {
    private let process = Process()
    private let prefix: Prefix

    public var logURL: URL { prefix.url.appending(path: "neutron.log") }

    public init(prefix: Prefix, command: Command, onExit: @escaping @Sendable (Int32) -> Void) throws {
        self.prefix = prefix
        FileManager.default.createFile(atPath: prefix.url.appending(path: "neutron.log").path, contents: nil)
        let log = try FileHandle(forWritingTo: prefix.url.appending(path: "neutron.log"))
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.currentDirectoryURL = command.workingDirectory
        process.standardOutput = log
        process.standardError = log
        process.terminationHandler = { process in
            try? log.close()
            onExit(process.terminationStatus)
        }
        try process.run()
    }

    /// Stops the game and everything else running in its prefix.
    public func stop() {
        try? run(prefix.runtime.appending(path: "bin/wineserver"), ["-k"], env: prefix.environment(appID: nil))
    }
}
