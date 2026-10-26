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
