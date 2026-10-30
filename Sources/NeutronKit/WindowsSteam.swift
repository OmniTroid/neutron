import Foundation

/// Valve's Windows Steam client in its own prefix, which installs, updates and launches every game. Neutron runs
/// the unmodified client with its window shown and talks to it only through Valve's entry points: `steam.exe` command-line options and
/// `steam://` URLs, which a second `steam.exe` forwards to the running client. State comes from the registry
/// values the client writes.
public struct WindowsSteam: Sendable {
    public let prefix: URL
    public let wine: URL
    static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!

    public init(prefix: URL = Paths.steamPrefix, runtime: URL? = nil) throws {
        self.prefix = prefix
        wine = try (runtime ?? Runtime.url(dist: Paths.dist())).appending(path: "bin/wine")
    }

    var steamExe: URL { prefix.appending(path: "drive_c/Program Files (x86)/Steam/steam.exe") }
    /// Wine's output for the client and every game it starts.
    public var log: URL { prefix.appending(path: "neutron.log") }
    public var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        // the runtime's host libraries (GnuTLS, FreeType, MoltenVK); Wine dlopens them by bare name
        let lib = wine.deletingLastPathComponent().deletingLastPathComponent().appending(path: "lib").path
        env["DYLD_FALLBACK_LIBRARY_PATH"] = [lib, env["DYLD_FALLBACK_LIBRARY_PATH"]].compactMap { $0 }.joined(separator: ":")
        // loaddll shows which renderer each process loads; see GraphicsCheck
        env["WINEDEBUG"] = "-all,+pid,+loaddll"
        // DXMT, never a copy a game ships (e.g. DXVK)
        env["WINEDLLOVERRIDES"] = "d3d9,d3d10core,d3d11,dxgi=b;winemenubuilder.exe=d;winedbg.exe=d"
        // Steam's UI hangs under Wine's msync/esync
        env["WINEMSYNC"] = "0"
        env["WINEESYNC"] = "0"
        // Steam's browser renders in a GPU process into a window its UI process owns
        env["DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN"] = "1"
        return env
    }

    // MARK: Lifecycle

    public func installIfNeeded() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: steamExe.path) {
            let (data, _) = try await URLSession.shared.data(from: WindowsSteam.installerURL)
            let installer = prefix.appending(path: "SteamSetup.exe")
            try data.write(to: installer)
            defer { try? fm.removeItem(at: installer) }
            guard try run(wine, [installer.path, "/S"], env: environment) == 0, fm.fileExists(atPath: steamExe.path) else {
                throw NeutronError("Windows Steam installer failed")
            }
        }
        // steam.exe shows only hidden helper windows; the Dock icon belongs to steamwebhelper.exe's windows
        let userReg = (try? String(contentsOf: prefix.appending(path: "user.reg"), encoding: .utf8)) ?? ""
        if !userReg.contains(#"[Software\\Wine\\AppDefaults\\steam.exe\\Mac Driver]"#) {
            _ = try run(wine, ["reg", "add", #"HKCU\Software\Wine\AppDefaults\steam.exe\Mac Driver"#,
                               "/v", "ShowInDock", "/t", "REG_SZ", "/d", "N", "/f"], env: environment)
        }
    }

    public var installed: Bool { FileManager.default.fileExists(atPath: steamExe.path) }

    /// Starts the client, or shows the running one's window. `silent` keeps a new client in the tray, as for game
    /// launches. The first start downloads ~600 MB of updates; Steam restarts itself during it and under Wine
    /// sometimes crashes, so it is relaunched (it resumes) until its UI is up.
    public func start(silent: Bool = false, timeout: Duration = .seconds(1800)) async throws {
        try await installIfNeeded()
        if steamProcessExists() {
            if !silent { try forward(["steam://open/main"]) }
            return
        }
        let deadline = ContinuousClock.now + timeout
        var launches = 0
        var process: Process?
        var exitedAt: ContinuousClock.Instant?
        while ContinuousClock.now < deadline {
            if let running = process, !running.isRunning, exitedAt == nil { exitedAt = .now }
            let settled = exitedAt.map { ContinuousClock.now - $0 > .seconds(20) } ?? false
            if process == nil || (settled && !steamProcessExists()) {
                guard launches < 5 else { throw NeutronError("Windows Steam keeps exiting during startup") }
                launches += 1
                process = try launch(silent ? ["-silent"] : [])
                exitedAt = nil
            } else if steamProcessExists(), userInterfaceIsUp() {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw NeutronError("Windows Steam didn't come up within \(timeout)")
    }

    public func stop() async {
        if steamProcessExists() { _ = try? forward(["-shutdown"]) }
        for _ in 0..<30 where steamProcessExists() { try? await Task.sleep(for: .seconds(1)) }
        _ = try? run(wine.deletingLastPathComponent().appending(path: "wineserver"), ["-k"], env: environment)
    }

    // MARK: Games

    /// Opens Steam's own install dialog for the game; the user confirms it there.
    public func install(appID: UInt32) throws {
        try open("steam://install/\(appID)")
    }

    /// Opens Steam's own uninstall confirmation.
    public func uninstall(appID: UInt32) throws {
        try open("steam://uninstall/\(appID)")
    }

    public func launch(appID: UInt32) throws {
        try forward(["-applaunch", String(appID)])
    }

    /// Hands a steam:// URL to the client, e.g. `steam://nav/games/details/<appid>`.
    public func open(_ url: String) throws {
        try forward([url])
    }

    // MARK: State, from the registry the client writes

    public struct Status: Sendable, Equatable {
        public var running: Bool
        public var signedIn: Bool
        public var account: String?
        public var runningAppID: UInt32?
        /// Processes that rendered with something other than DXMT since Steam started.
        public var fallbacks: [GraphicsCheck.Fallback]

        public init(running: Bool, signedIn: Bool, account: String? = nil, runningAppID: UInt32? = nil,
                    fallbacks: [GraphicsCheck.Fallback] = []) {
            self.running = running
            self.signedIn = signedIn
            self.account = account
            self.runningAppID = runningAppID
            self.fallbacks = fallbacks
        }
    }

    public func fallbacks() -> [GraphicsCheck.Fallback] {
        func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        let logs = steamExe.deletingLastPathComponent().appending(path: "logs")
        return GraphicsCheck.fallbacks(inLog: read(log))
            + GraphicsCheck.steamBrowserFallbacks(webhelperLog: read(logs.appending(path: "webhelper.txt")),
                                                  cefLog: read(logs.appending(path: "cef_log.txt")))
    }

    /// The Mac process that owns Steam's windows: the browser process of steamwebhelper.
    public func windowProcessID() -> pid_t? {
        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-axww", "-o", "pid=,command="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return output.split(separator: "\n").lazy
            .filter { $0.contains("steamwebhelper.exe") && !$0.contains("--type=") }
            .compactMap { pid_t($0.split(separator: " ").first ?? "") }
            .first
    }

    public func status() throws -> Status {
        guard steamProcessExists() else { return Status(running: false, signedIn: false, fallbacks: fallbacks()) }
        let activeUser = try registryValue(#"HKCU\Software\Valve\Steam\ActiveProcess"#, "ActiveUser").flatMap(WindowsSteam.dword)
        let runningApp = try registryValue(#"HKCU\Software\Valve\Steam"#, "RunningAppID").flatMap(WindowsSteam.dword)
        return Status(running: true, signedIn: (activeUser ?? 0) != 0,
                      account: try registryValue(#"HKCU\Software\Valve\Steam"#, "AutoLoginUser"),
                      runningAppID: runningApp.flatMap { $0 == 0 ? nil : $0 }, fallbacks: fallbacks())
    }

    // MARK: Plumbing

    /// A second steam.exe hands its command line to the running client over Steam's IPC and exits.
    func forward(_ arguments: [String]) throws {
        guard try run(wine, [steamExe.path] + arguments, env: environment) == 0 else {
            throw NeutronError("Steam didn't accept \(arguments.joined(separator: " "))")
        }
    }

    func launch(_ arguments: [String]) throws -> Process {
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        let process = Process()
        process.executableURL = wine
        process.arguments = [steamExe.path] + arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        return process
    }

    /// The UI process the client starts once it is past its updater.
    func userInterfaceIsUp() -> Bool {
        processCommandLines().contains { $0.lowercased().contains("steamwebhelper.exe") }
    }

    /// Steam relaunches itself after updating, so the process Neutron started isn't a reliable signal.
    func steamProcessExists() -> Bool {
        processCommandLines().contains { $0.lowercased().contains(#"steam\steam.exe"#) }
    }

    func processCommandLines() -> [String] {
        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-axo", "command"]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return [] }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return output.split(separator: "\n").map(String.init)
    }

    /// Reads a value through `wine reg query`, which asks the running wineserver, so it is current.
    func registryValue(_ key: String, _ name: String) throws -> String? {
        let process = Process()
        process.executableURL = wine
        process.arguments = ["reg", "query", key, "/v", name]
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return WindowsSteam.parseRegQuery(output, name: name)
    }

    /// Value of `name` in `reg query` output, e.g. `    ActiveUser    REG_DWORD    0x3a0d4f9`.
    static func parseRegQuery(_ output: String, name: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.count >= 3, fields[0].caseInsensitiveCompare(name) == .orderedSame, fields[1].hasPrefix("REG_") {
                return fields[2...].joined(separator: " ")
            }
        }
        return nil
    }

    static func dword(_ value: String) -> UInt32? {
        value.hasPrefix("0x") ? UInt32(value.dropFirst(2), radix: 16) : UInt32(value)
    }
}
