import CoreGraphics
import Foundation
import ImageIO

/// The Windows Steam client, run headless in its own prefix and driven through Chromium DevTools.
/// Proof of concept for games that need Valve's own client (VAC). The prefix uses Wine's null display
/// driver, so Steam never shows a window; its UI still runs and renders offscreen for DevTools.
public struct WindowsSteam: Sendable {
    public let prefix: URL
    public let wine: URL
    static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    // Chromium's software path is the one that runs under Wine; its GPU path needs cross-process swap chains
    static let launchFlags = ["-cef-disable-gpu", "-cef-disable-gpu-compositing", "-silent"]

    public init(prefix: URL = Paths.prefixes.appending(path: "steam"), wine: URL? = nil) throws {
        self.prefix = prefix
        if let wine {
            self.wine = wine
        } else if let override = ProcessInfo.processInfo.environment["NEUTRON_STEAM_WINE"] {
            self.wine = URL(filePath: override)
        } else {
            self.wine = Paths.neutron.appending(path: "downloads/wine-staging-11.18/Wine Staging.app/Contents/Resources/wine/bin/wine")
        }
        guard FileManager.default.fileExists(atPath: self.wine.path) else {
            throw NeutronError("Windows Steam runtime missing at \(self.wine.path); set NEUTRON_STEAM_WINE")
        }
    }

    var steamDir: URL { prefix.appending(path: "drive_c/Program Files (x86)/Steam") }
    var portFile: URL { prefix.appending(path: "neutron-devtools-port") }

    /// DevTools of the instance Neutron last started; Steam keeps its launch arguments across self-restarts.
    var devTools: DevTools? {
        (try? String(contentsOf: portFile, encoding: .utf8)).flatMap { UInt16($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .map(DevTools.init(port:))
    }

    func requireDevTools() throws -> DevTools {
        guard let devTools else { throw NeutronError("Windows Steam isn't running; run `neutron windows-steam start`") }
        return devTools
    }
    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        return env
    }

    // MARK: Lifecycle

    public func installIfNeeded() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
        let userReg = prefix.appending(path: "user.reg")
        if !fm.fileExists(atPath: userReg.path) {
            // select the null display driver before Wine first creates the prefix, so even its setup shows nothing
            try #"""
                WINE REGISTRY Version 2
                ;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

                #arch=win64

                [Software\\Wine\\Drivers]
                "Graphics"="null"

                """#.write(to: userReg, atomically: true, encoding: .utf8)
        }

        if !fm.fileExists(atPath: steamDir.appending(path: "Steam.exe").path) {
            let (data, _) = try await URLSession.shared.data(from: WindowsSteam.installerURL)
            let installer = prefix.appending(path: "SteamSetup.exe")
            try data.write(to: installer)
            defer { try? fm.removeItem(at: installer) }
            guard try run(wine, [installer.path, "/S"], env: environment) == 0,
                  fm.fileExists(atPath: steamDir.appending(path: "Steam.exe").path) else {
                throw NeutronError("Windows Steam installer failed")
            }
        }
        // this marker would make Steam also open DevTools on the fixed port 8080
        try? fm.removeItem(at: steamDir.appending(path: ".cef-enable-remote-debugging"))
    }

    public var isRunning: Bool {
        get async { (try? await devTools?.targets()) != nil }
    }

    /// Starts the client and waits until its UI is up. The first start downloads ~600 MB of updates, during
    /// which Steam restarts itself and, under Wine, sometimes crashes; it is relaunched and resumes.
    public func start(timeout: Duration = .seconds(900)) async throws {
        try await installIfNeeded()
        if await isRunning { return }
        try String(try DevTools.freeLoopbackPort()).write(to: portFile, atomically: true, encoding: .utf8)
        let deadline = ContinuousClock.now + timeout
        var launches = 0
        var process: Process?
        var exitedAt: ContinuousClock.Instant?
        while ContinuousClock.now < deadline {
            // ready once Steam's UI has decided between the login and main windows
            if !(await popupNames()).isEmpty { return }

            if let running = process, !running.isRunning, exitedAt == nil { exitedAt = .now }
            let idle = exitedAt.map { ContinuousClock.now - $0 > .seconds(20) } ?? false
            if process == nil || (idle && !steamProcessExists()) {
                guard launches < 5 else { throw NeutronError("Windows Steam keeps exiting during startup") }
                launches += 1
                process = try launchSteam()
                exitedAt = nil
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw NeutronError("Windows Steam didn't come up within \(timeout)")
    }

    func launchSteam() throws -> Process {
        let process = Process()
        process.executableURL = wine
        process.arguments = [steamDir.appending(path: "Steam.exe").path] + WindowsSteam.launchFlags
            + ["-cef-enable-debugging", "-devtools-port", String(try requireDevTools().port)]
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Steam relaunches itself after updating, so the process Neutron started isn't a reliable signal.
    func steamProcessExists() -> Bool {
        let ps = Process()
        ps.executableURL = URL(filePath: "/bin/ps")
        ps.arguments = ["-axo", "command"]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return false }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return output.split(separator: "\n").contains { $0.lowercased().contains(#"steam\steam.exe"#) }
    }

    public func stop() async {
        _ = try? await devTools?.evaluate(in: "SharedJSContext", "SteamClient.User.StartShutdown(false)")
        try? await Task.sleep(for: .seconds(5))
        _ = try? run(wine.deletingLastPathComponent().appending(path: "wineserver"), ["-k"], env: environment)
        try? FileManager.default.removeItem(at: portFile)
    }

    func popupNames() async -> [String] {
        let script = "JSON.stringify([...(window.g_PopupManager?.GetPopups() ?? [])].map(p => p.m_strName))"
        guard case .string(let json)? = try? await devTools?.evaluate(in: "SharedJSContext", script),
              let names = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return [] }
        return names
    }

    // MARK: Login

    /// The login page's current QR code (Steam rotates it), as a square grid of dark modules.
    public func loginQRCode() async throws -> [[Bool]]? {
        let script = """
            (() => {
              const img = [...document.images].find(i => i.src.startsWith('blob:') && i.naturalWidth > 20
                                                       && i.naturalWidth === i.naturalHeight);
              if (!img) return null;
              const c = document.createElement('canvas');
              c.width = img.naturalWidth; c.height = img.naturalHeight;
              c.getContext('2d').drawImage(img, 0, 0);
              return c.toDataURL('image/png');
            })()
            """
        guard case .string(let dataURL)? = try await requireDevTools().evaluate(in: "Sign in to Steam", script),
              let base64 = dataURL.split(separator: ",").last,
              let png = Data(base64Encoded: String(base64)) else { return nil }
        return WindowsSteam.modules(fromPNG: png)
    }

    public var isLoginScreenShown: Bool {
        get async { await popupNames().contains { $0.hasPrefix("SP DesktopLoginWindow") } }
    }

    /// Account name of the signed-in user, if any.
    public func signedInAccount() async -> String? {
        let script = """
            new Promise(resolve => {
              const h = SteamClient.User.RegisterForCurrentUserChanges(u => { h?.unregister?.(); resolve(u?.strAccountName ?? null); });
              setTimeout(() => resolve(null), 2000);
            })
            """
        guard case .string(let name)? = try? await devTools?.evaluate(in: "SharedJSContext", script), !name.isEmpty else { return nil }
        return name
    }

    // MARK: Games

    public func launch(appID: UInt32) async throws {
        _ = try await requireDevTools().evaluate(in: "SharedJSContext", "SteamClient.Apps.RunGame('\(appID)', '', -1, 100)")
    }

    public func install(appID: UInt32) async throws {
        _ = try await requireDevTools().evaluate(in: "SharedJSContext", "SteamClient.Installs.OpenInstallWizard([\(appID)])")
    }

    static func modules(fromPNG png: Data) -> [[Bool]]? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let size = image.width
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let context = CGContext(data: &pixels, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        return (0..<size).map { y in (0..<size).map { x in pixels[(y * size + x) * 4] < 128 } }
    }
}

/// Minimal Chromium DevTools client for Steam's CEF pages.
public struct DevTools: Sendable {
    public struct Target: Decodable, Sendable {
        public let title: String
        public let type: String
        public let webSocketDebuggerUrl: URL?
    }

    public enum Value: Sendable, Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case other(String)
    }

    public let port: UInt16

    public func targets() async throws -> [Target] {
        // a fresh connection each time, so a pooled keep-alive connection can't stick to whoever answered first
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/json/list")!)
        request.timeoutInterval = 3
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([Target].self, from: data)
    }

    /// An unused loopback port: bind port 0 and read back what the OS picked.
    public static func freeLoopbackPort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NeutronError("socket failed") }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, length) == 0 && getsockname(fd, $0, &length) == 0
            }
        }
        guard bound else { throw NeutronError("couldn't find a free port") }
        return UInt16(bigEndian: address.sin_port)
    }

    public func evaluate(in title: String, _ expression: String) async throws -> Value? {
        guard let target = try await targets().first(where: { $0.title == title }) else {
            throw NeutronError("Steam page \"\(title)\" isn't open")
        }
        return try await evaluate(in: target, expression)
    }

    public func evaluate(in target: Target, _ expression: String) async throws -> Value? {
        guard let url = target.webSocketDebuggerUrl else { throw NeutronError("\(target.title) has no debugger") }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let message: [String: Any] = ["id": 1, "method": "Runtime.evaluate",
                                      "params": ["expression": expression, "returnByValue": true, "awaitPromise": true]]
        let body = String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)
        try await socket.send(.string(body))
        while true {
            guard case .string(let text) = try await socket.receive(),
                  let reply = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  reply["id"] as? Int == 1 else { continue }
            let result = reply["result"] as? [String: Any]
            if let exception = result?["exceptionDetails"] as? [String: Any] {
                let description = (exception["exception"] as? [String: Any])?["description"] as? String
                throw NeutronError("Steam script failed: \(description ?? "\(exception)")")
            }
            switch (result?["result"] as? [String: Any])?["value"] {
            case let string as String: return .string(string)
            case let bool as Bool: return .bool(bool)
            case let number as NSNumber: return .number(number.doubleValue)
            case nil, is NSNull: return .null
            case let other?: return .other("\(other)")
            }
        }
    }
}
