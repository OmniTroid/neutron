import Foundation
import Testing
@testable import NeutronKit

let testApp: KeyValue = .object([
    ("appid", .int(12345)),
    ("common", .object([("name", .string("Test Game")), ("oslist", .string("windows,macos"))])),
    ("config", .object([
        ("installdir", .string("Test Game")),
        ("launch", .object([
            ("0", .object([("executable", .string("TestGame.app")), ("type", .string("default")),
                           ("config", .object([("oslist", .string("macos"))]))])),
            ("1", .object([("executable", .string(#"bin\win32\game.exe"#)), ("type", .string("default")),
                           ("config", .object([("oslist", .string("windows")), ("osarch", .string("32"))]))])),
            ("2", .object([("executable", .string("editor.exe")), ("type", .string("editor"))])),
            ("3", .object([("executable", .string(#"bin\win64\game.exe"#)),
                           ("arguments", .string(#"-dx11 "-name=a b""#)),
                           ("workingdir", .string(#"bin\win64"#)),
                           ("config", .object([("oslist", .string("windows")), ("osarch", .int(64))]))])),
            ("4", .object([("executable", .string("beta.exe")),
                           ("config", .object([("oslist", .string("windows")), ("osarch", .int(64)),
                                               ("betakey", .string("beta"))]))])),
        ])),
    ])),
])

func encodeAppInfoV29(_ apps: [(UInt32, KeyValue)]) -> Data {
    var strings: [String] = []
    func key(_ name: String) -> Data {
        if !strings.contains(name) { strings.append(name) }
        return withUnsafeBytes(of: UInt32(strings.firstIndex(of: name)!).littleEndian) { Data($0) }
    }
    func kv(_ node: KeyValue) -> Data {
        var out = Data()
        for (k, v) in node.children {
            switch v {
            case .object: out += [0x00] + key(k) + kv(v)
            case .string(let s): out += [0x01] + key(k) + Data(s.utf8) + [0]
            case .int(let i): out += [0x02] + key(k) + withUnsafeBytes(of: Int32(i).littleEndian) { Data($0) }
            case .float(let f): out += [0x03] + key(k) + withUnsafeBytes(of: f.bitPattern.littleEndian) { Data($0) }
            }
        }
        return out + [0x08]
    }
    func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    var body = Data()
    for (id, info) in apps {
        let data = Data(count: 60) + kv(.object([("appinfo", info)]))
        body += le(id) + le(UInt32(data.count)) + data
    }
    body += le(UInt32(0))
    let table = le(UInt32(strings.count)) + strings.reduce(Data()) { $0 + Data($1.utf8) + [0] }
    return le(UInt32(0x0756_4429)) + le(UInt32(1)) + le(Int64(16 + body.count)) + body + table
}

struct AppInfoTests {
    let dir: URL
    let path: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appending(path: "appinfo.vdf")
        let other: KeyValue = .object([("appid", .int(10)), ("common", .object([("name", .string("Other"))]))])
        try encodeAppInfoV29([(10, other), (12345, testApp)]).write(to: path)
    }

    @Test func readsAppFromCache() throws {
        #expect(try AppInfo.read(appID: 12345, from: path) == testApp)
        #expect(try AppInfo.read(appID: 999, from: path) == nil)
    }

    @Test func prefersWindows64BitDefaultLaunch() throws {
        let launch = AppInfo.windowsLaunch(try #require(try AppInfo.read(appID: 12345, from: path)))
        #expect(launch?["executable"]?.text == #"bin\win64\game.exe"#)
    }

    @Test func noLaunchWithoutWindows() {
        let macOnly: KeyValue = .object([("config", .object([("launch", .object([testApp["config"]!["launch"]!.children[0]]))]))])
        #expect(AppInfo.windowsLaunch(macOnly) == nil)
    }

    @Test func installedGameResolvesLaunch() throws {
        let game = try #require(InstalledGame(appID: 12345, appInfo: testApp))
        #expect(game.name == "Test Game")
        #expect(game.is64Bit)

        try FileManager.default.createDirectory(at: Library.directory(appID: 12345, library: dir), withIntermediateDirectories: true)
        try Library.save(game, library: dir)
        let launch = Library.launch(try Library.game(appID: 12345, library: dir), library: dir)
        #expect(launch.exe == dir.appending(path: "12345/bin/win64/game.exe"))
        #expect(launch.workingDirectory == dir.appending(path: "12345/bin/win64"))
        #expect(launch.arguments == ["-dx11", "-name=a b"])
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Paths.steamAppInfo.path)))
    func readsLocalSteamCache() throws {
        let tf2 = try #require(try AppInfo.read(appID: 440))
        let game = try #require(InstalledGame(appID: 440, appInfo: tf2))
        #expect(game.executable == "tf_win64.exe")
        #expect(game.is64Bit)
    }

    @Test func prefersDirect3D11AlternativeWithoutDefault() {
        let peakLike: KeyValue = .object([("config", .object([("launch", .object([
            ("5", .object([("executable", .string("PEAK.exe")), ("type", .string("option1")),
                           ("description", .string("PEAK using DX12")),
                           ("config", .object([("oslist", .string("windows")), ("osarch", .int(64))]))])),
            ("6", .object([("executable", .string("PEAK.exe")), ("type", .string("option2")),
                           ("arguments", .string("-force-d3d11")), ("description", .string("PEAK using DX11")),
                           ("config", .object([("oslist", .string("windows")), ("osarch", .int(64))]))])),
        ]))]))])
        #expect(AppInfo.windowsLaunch(peakLike)?["arguments"]?.text == "-force-d3d11")
    }

    @Test func splitsQuotedArguments() {
        #expect(Library.splitArguments(#"  -a  "b c" ""  -d"#) == ["-a", "b c", "", "-d"])
    }
}

struct InstallSessionParsingTests {
    @Test func parsesProgressLines() {
        let events = InstallSession.parse(line: "42.50% /Users/x/Library/Application Support/Neutron/library/440/tf/tf2_misc_dir.vpk")
        guard case .progress(let value) = events.first, case .status(let file) = events.last else {
            Issue.record("expected progress and status, got \(events)")
            return
        }
        #expect(value == 0.425)
        #expect(file == "tf2_misc_dir.vpk")
    }

    @Test func detectsPrompts() {
        #expect(InstallSession.prompt(in: #"Enter account password for "dave": "#) == .password)
        #expect(InstallSession.prompt(in: "STEAM GUARD! Please enter your 2-factor auth code from your authenticator app: ") == .guardCode)
        #expect(InstallSession.prompt(in: "STEAM GUARD! Please enter the auth code sent to the email at d***@gmail.com: ")
            == .emailCode("d***@gmail.com"))
        #expect(InstallSession.prompt(in: "Connecting to Steam3...") == nil)
        guard case .prompt(.mobileConfirmation) = InstallSession.parse(line: "STEAM GUARD! Use the Steam Mobile App to confirm your sign in...").first else {
            Issue.record("expected mobile confirmation prompt")
            return
        }
    }
}

struct CloudSavesTests {
    func rule(_ root: String, _ path: String, _ pattern: String, _ platform: String?) -> KeyValue {
        var pairs: [(key: String, value: KeyValue)] = [("root", .string(root)), ("path", .string(path)), ("pattern", .string(pattern))]
        if let platform { pairs.append(("platforms", .object([("1", .string(platform))]))) }
        return .object(pairs)
    }

    @Test func pairsWindowsRuleWithMacRule() {
        let peak: KeyValue = .object([("ufs", .object([("savefiles", .object([
            ("0", rule("WinAppDataLocalLow", "LandCrab/PEAK", "*.peak", "Windows")),
            ("1", rule("LinuxXdgConfigHome", "unity3d/LandCrab/PEAK", "*.peak", "Linux")),
            ("2", rule("MacAppSupport", "unity.LandCrab.PEAK", "*.peak", "MacOS")),
        ]))]))])
        #expect(CloudSaves.links(for: peak) == [SaveLink(windowsRoot: "WinAppDataLocalLow", windowsPath: "LandCrab/PEAK",
                                                         macRoot: "MacAppSupport", macPath: "unity.LandCrab.PEAK")])
    }

    @Test func appliesRootOverride() {
        let game: KeyValue = .object([("ufs", .object([
            ("savefiles", .object([("0", rule("WinMyDocuments", "My Games/Thing", "*", nil))])),
            ("rootoverrides", .object([("0", .object([("root", .string("WinMyDocuments")), ("os", .string("MacOS")),
                                                      ("useinstead", .string("MacAppSupport")), ("addpath", .string("Thing"))]))])),
        ]))])
        #expect(CloudSaves.links(for: game) == [SaveLink(windowsRoot: "WinMyDocuments", windowsPath: "My Games/Thing",
                                                         macRoot: "MacAppSupport", macPath: "Thing/My Games/Thing")])
    }

    @Test func skipsTokensAndWindowsOnlyRules() {
        let game: KeyValue = .object([("ufs", .object([("savefiles", .object([
            ("0", rule("WinAppDataRoaming", "Thing/{64BitSteamID}", "*", "Windows")),
            ("1", rule("WinAppDataRoaming", "Other", "*.sav", "Windows")),
        ]))]))])
        #expect(CloudSaves.links(for: game).isEmpty)
    }

    @Test func linksWithoutClobberingSaves() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let prefix = root.appending(path: "pfx"), home = root.appending(path: "home")
        let link = SaveLink(windowsRoot: "WinAppDataLocalLow", windowsPath: "LandCrab/PEAK", macRoot: "MacAppSupport", macPath: "unity.LandCrab.PEAK")
        let windowsDir = prefix.appending(path: "drive_c/users/me/AppData/LocalLow/LandCrab/PEAK")
        let macDir = home.appending(path: "Library/Application Support/unity.LandCrab.PEAK")

        #expect(try CloudSaves.apply([link], prefix: prefix, home: home, user: "me").isEmpty)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: windowsDir.path) == macDir.path)
        #expect(try CloudSaves.apply([link], prefix: prefix, home: home, user: "me").isEmpty)

        try FileManager.default.removeItem(at: windowsDir)
        try FileManager.default.createDirectory(at: windowsDir, withIntermediateDirectories: true)
        try Data("save".utf8).write(to: windowsDir.appending(path: "slot.peak"))
        #expect(try CloudSaves.apply([link], prefix: prefix, home: home, user: "me").count == 1)
        #expect(FileManager.default.fileExists(atPath: windowsDir.appending(path: "slot.peak").path))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Paths.steamAppInfo.path)))
    func peakFromLocalSteamCache() throws {
        let peak = try #require(try AppInfo.read(appID: 3527290))
        #expect(CloudSaves.links(for: peak).first?.macPath == "unity.LandCrab.PEAK")
    }
}

struct InstallSizeTests {
    func depot(_ size: Int64, _ config: [(key: String, value: KeyValue)] = [], dlc: Bool = false) -> KeyValue {
        var pairs: [(key: String, value: KeyValue)] = [("manifests", .object([("public", .object([("size", .string(String(size)))]))]))]
        if !config.isEmpty { pairs.append(("config", .object(config))) }
        if dlc { pairs.append(("dlcappid", .string("123"))) }
        return .object(pairs)
    }

    @Test func sumsMatchingWindowsDepots() {
        let app: KeyValue = .object([("depots", .object([
            ("1", depot(1000)),
            ("2", depot(200, [("oslist", .string("windows")), ("osarch", .string("64"))])),
            ("3", depot(50, [("oslist", .string("windows")), ("osarch", .string("32"))])),
            ("4", depot(70, [("oslist", .string("macos"))])),
            ("5", depot(30, [("language", .string("german"))])),
            ("6", depot(10, [("lowviolence", .string("1"))])),
            ("7", depot(5, dlc: true)),
            ("branches", .object([("public", .object([("buildid", .string("1"))]))])),
        ]))])
        #expect(AppInfo.windowsInstallSize(app, is64Bit: true) == 1200)
        #expect(AppInfo.windowsInstallSize(app, is64Bit: false) == 1050)
        #expect(AppInfo.windowsInstallSize(.object([]), is64Bit: true) == nil)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Paths.steamAppInfo.path)))
    func peakSizeFromLocalSteamCache() throws {
        let peak = try #require(try AppInfo.read(appID: 3527290))
        #expect(AppInfo.windowsInstallSize(peak, is64Bit: true) == 16_440_905_716)
    }
}
