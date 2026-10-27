import CoreGraphics
import Foundation
import ImageIO

/// The Windows Steam client, run headless in its own prefix and driven through Chromium DevTools.
/// Proof of concept for games that need Valve's own client (VAC); its windows are kept hidden.
public struct WindowsSteam: Sendable {
    public let prefix: URL
    public let wine: URL
    static let installerURL = URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!
    static let devTools = URL(string: "http://127.0.0.1:8080")!
    // Chromium's software path is the one that renders under Wine; its GPU path can't present here
    static let launchFlags = ["-cef-disable-gpu", "-cef-disable-gpu-compositing", "-cef-disable-sandbox", "-silent"]

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
    var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefix.path
        env["WINEDEBUG"] = "-all"
        return env
    }

    // MARK: Lifecycle

    public func installIfNeeded() async throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: steamDir.appending(path: "Steam.exe").path) {
            try fm.createDirectory(at: prefix, withIntermediateDirectories: true)
            let (data, _) = try await URLSession.shared.data(from: WindowsSteam.installerURL)
            let installer = prefix.appending(path: "SteamSetup.exe")
            try data.write(to: installer)
            defer { try? fm.removeItem(at: installer) }
            guard try run(wine, [installer.path, "/S"], env: environment) == 0,
                  fm.fileExists(atPath: steamDir.appending(path: "Steam.exe").path) else {
                throw NeutronError("Windows Steam installer failed")
            }
        }
        // Steam reads this marker at startup and opens DevTools on 127.0.0.1:8080
        fm.createFile(atPath: steamDir.appending(path: ".cef-enable-remote-debugging").path, contents: nil)
    }

    public var isRunning: Bool {
        get async { (try? await DevTools.targets()) != nil }
    }

    /// Starts the client (first start downloads its ~600 MB update) and waits until DevTools answers.
    public func start(timeout: Duration = .seconds(600)) async throws {
        try await installIfNeeded()
        if await isRunning { return }
        let process = Process()
        process.executableURL = wine
        process.arguments = [steamDir.appending(path: "Steam.exe").path] + WindowsSteam.launchFlags
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if (try? await DevTools.targets()) != nil {
                await hideWindows()
                // ready once the hide hook is in and Steam has decided between the login and main windows
                if (try? await installHideHook()) == true, !(await popupNames()).isEmpty { return }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw NeutronError("Windows Steam didn't come up within \(timeout)")
    }

    /// Hides every Steam window from inside Steam's always-running SharedJSContext, including windows Steam
    /// creates later; returns false until Steam's popup manager exists.
    @discardableResult
    func installHideHook() async throws -> Bool {
        let script = """
            (() => {
              if (window.__neutronHideHook) return true;
              if (!window.g_PopupManager) return false;
              const hide = p => { try { p.m_popup?.SteamClient?.Window?.HideWindow(); } catch (e) {} };
              g_PopupManager.AddPopupCreatedCallback(p => {
                p.m_bCreateHidden = true;
                hide(p); setTimeout(() => hide(p), 100); setTimeout(() => hide(p), 1000);
              });
              for (const p of g_PopupManager.GetPopups()) hide(p);
              window.__neutronHideHook = true;
              return true;
            })()
            """
        return try await DevTools.evaluate(in: "SharedJSContext", script) == .bool(true)
    }

    func popupNames() async -> [String] {
        let script = "JSON.stringify([...(window.g_PopupManager?.GetPopups() ?? [])].map(p => p.m_strName))"
        guard case .string(let json)? = try? await DevTools.evaluate(in: "SharedJSContext", script),
              let names = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) else { return [] }
        return names
    }

    public func stop() async {
        _ = try? await DevTools.evaluate(in: "SharedJSContext", "SteamClient.User.StartShutdown(false)")
        try? await Task.sleep(for: .seconds(5))
        _ = try? run(wine.deletingLastPathComponent().appending(path: "wineserver"), ["-k"], env: environment)
    }

    /// Hides every Steam window; call repeatedly, since Steam opens new ones (login, main window, dialogs).
    public func hideWindows() async {
        guard let targets = try? await DevTools.targets() else { return }
        for target in targets where target.type == "page" && target.title != "SharedJSContext" {
            _ = try? await DevTools.evaluate(in: target, "SteamClient.Window.HideWindow()")
        }
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
        guard case .string(let dataURL)? = try await DevTools.evaluate(in: "Sign in to Steam", script),
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
        guard case .string(let name)? = try? await DevTools.evaluate(in: "SharedJSContext", script), !name.isEmpty else { return nil }
        return name
    }

    // MARK: Games

    public func launch(appID: UInt32) async throws {
        _ = try await DevTools.evaluate(in: "SharedJSContext", "SteamClient.Apps.RunGame('\(appID)', '', -1, 100)")
    }

    public func install(appID: UInt32) async throws {
        _ = try await DevTools.evaluate(in: "SharedJSContext", "SteamClient.Installs.OpenInstallWizard([\(appID)])")
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
public enum DevTools {
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

    public static func targets() async throws -> [Target] {
        // a fresh connection each time: before Steam binds 127.0.0.1:8080 another server on *:8080 may answer,
        // and a pooled keep-alive connection would keep going there
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: WindowsSteam.devTools.appending(path: "json/list"))
        request.timeoutInterval = 3
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([Target].self, from: data)
    }

    public static func evaluate(in title: String, _ expression: String) async throws -> Value? {
        guard let target = try await targets().first(where: { $0.title == title }) else {
            throw NeutronError("Steam page \"\(title)\" isn't open")
        }
        return try await evaluate(in: target, expression)
    }

    public static func evaluate(in target: Target, _ expression: String) async throws -> Value? {
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
