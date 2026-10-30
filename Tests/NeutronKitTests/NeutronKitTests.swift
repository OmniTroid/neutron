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
}

struct RuntimeTests {
    @Test func assemblesOverlayOntoBase() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
        let dist = root.appending(path: "dist"), cache = root.appending(path: "cache")
        func write(_ path: String, _ text: String) throws {
            let url = dist.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        func read(_ url: URL) throws -> String { String(decoding: try Data(contentsOf: url), as: UTF8.self) }

        try write("wine/bin/wine", "loader")
        try write("wine/lib/wine/x86_64-unix/ntdll.so", "ntdll")
        try write("wine/lib/wine/x86_64-windows/d3d11.dll", "wined3d")
        for file in Runtime.dxmtFiles { try write("overlays/dxmt/\(file)", "dxmt") }
        try write("overlays/dxmt/lib/wine/x86_64-unix/winemetal.so", "metal")

        let dxmt = try Runtime.url(dist: dist, cache: cache)
        #expect(try read(dxmt.appending(path: "lib/wine/x86_64-windows/d3d11.dll")) == "dxmt")
        #expect(try read(dxmt.appending(path: "lib/wine/x86_64-unix/winemetal.so")) == "metal")
        #expect(try read(dxmt.appending(path: "bin/wine")) == "loader")
        #expect(try read(dist.appending(path: "wine/lib/wine/x86_64-windows/d3d11.dll")) == "wined3d")

        let marker = dxmt.appending(path: "marker")
        try Data().write(to: marker)
        _ = try Runtime.url(dist: dist, cache: cache)
        #expect(fm.fileExists(atPath: marker.path), "unchanged inputs reuse the assembled runtime")

        try write("overlays/dxmt/lib/wine/x86_64-windows/d3d11.dll", "dxmt v2")
        let updated = try Runtime.url(dist: dist, cache: cache)
        #expect(try read(updated.appending(path: "lib/wine/x86_64-windows/d3d11.dll")) == "dxmt v2")
        #expect(!fm.fileExists(atPath: updated.appending(path: "marker").path))
    }
}

struct CompatDBTests {
    @Test func entries() throws {
        let json = #"""
        {"source": "s", "license": "l", "games": {
          "440": {"title": "Team Fortress 2", "status": "community", "renderer": "dxmt",
                  "anticheat": {"names": ["VAC"], "macVerdict": "warning"}},
          "3527290": {"title": "PEAK", "status": "verified-local", "renderer": "dxvk"},
          "1172470": {"title": "Apex Legends", "status": "blocked-anticheat",
                      "anticheat": {"names": ["Easy Anti-Cheat"], "macVerdict": "warning"}},
          "1": {"title": "X", "status": "anticheat-only", "anticheat": {"names": ["BattlEye"], "macVerdict": "blocked"}}
        }}
        """#
        let db = try JSONDecoder().decode(CompatDB.self, from: Data(json.utf8))
        let tf2 = try #require(db.entry(appID: 440))
        #expect(tf2.renderer == "dxmt" && tf2.usesVAC && !tf2.blocked && tf2.tested)
        #expect(db.entry(appID: 1172470)?.blocked == true)
        #expect(db.entry(appID: 1)?.blocked == true && db.entry(appID: 1)?.tested == false)
        #expect(db.entry(appID: 2) == nil)
    }

    @Test func bundledDatabaseLoads() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../data/compat.json")
        #expect(try CompatDB.load(from: url).games.count > 1000)
    }
}

struct WindowsSteamRegistryTests {
    @Test func regQuery() {
        let output = "\r\nHKEY_CURRENT_USER\\Software\\Valve\\Steam\\ActiveProcess\r\n    ActiveUser    REG_DWORD    0x3a0d4f9\r\n\r\n"
        #expect(WindowsSteam.parseRegQuery(output, name: "ActiveUser") == "0x3a0d4f9")
        #expect(WindowsSteam.parseRegQuery(output, name: "RunningAppID") == nil)
        #expect(WindowsSteam.dword("0x3a0d4f9") == 0x3a0d4f9)
        #expect(WindowsSteam.dword("440") == 440)
        #expect(WindowsSteam.parseRegQuery("    AutoLoginUser    REG_SZ    some user\n", name: "AutoLoginUser") == "some user")
    }
}

struct SteamAppsTests {
    @Test func parsesTextKeyValues() throws {
        let vdf = try KeyValue.parse(text: #"""
        "libraryfolders"
        {
            // comment
            "0"
            {
                "path"		"C:\\Program Files (x86)\\Steam"
                "apps" { "440" "123" }
            }
        }
        """#)
        #expect(vdf["libraryfolders"]?["0"]?["path"]?.text == #"C:\Program Files (x86)\Steam"#)
        #expect(vdf["libraryfolders"]?["0"]?["apps"]?["440"]?.text == "123")
    }

    @Test func readsManifestsFromLibraryFolders() throws {
        let fm = FileManager.default
        let prefix = fm.temporaryDirectory.appending(path: UUID().uuidString)
        let steam = prefix.appending(path: "drive_c/Program Files (x86)/Steam")
        let steamapps = steam.appending(path: "steamapps")
        try fm.createDirectory(at: steamapps, withIntermediateDirectories: true)
        try fm.createDirectory(at: prefix.appending(path: "dosdevices"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: prefix.appending(path: "dosdevices/c:").path, withDestinationPath: "../drive_c")
        try #"""
        "libraryfolders" { "0" { "path" "C:\\Program Files (x86)\\Steam" } }
        """#.write(to: steamapps.appending(path: "libraryfolders.vdf"), atomically: true, encoding: .utf8)
        try #"""
        "AppState" { "appid" "440" "StateFlags" "4" "installdir" "Team Fortress 2" "SizeOnDisk" "100" }
        """#.write(to: steamapps.appending(path: "appmanifest_440.acf"), atomically: true, encoding: .utf8)
        try #"""
        "AppState" { "appid" "730" "StateFlags" "1026" "installdir" "CS2" "BytesToDownload" "200" "BytesDownloaded" "50" }
        """#.write(to: steamapps.appending(path: "appmanifest_730.acf"), atomically: true, encoding: .utf8)

        let states = SteamApps.states(steam: steam, prefix: prefix)
        let tf2 = try #require(states[440])
        #expect(tf2.installed && !tf2.updating && tf2.sizeOnDisk == 100)
        #expect(tf2.directory.resolvingSymlinksInPath() == steamapps.appending(path: "common/Team Fortress 2").resolvingSymlinksInPath())
        let cs2 = try #require(states[730])
        #expect(!cs2.installed && cs2.updating && cs2.progress == 0.25)
    }
}

struct GraphicsCheckTests {
    @Test func flagsRenderersOtherThanDXMT() {
        let log = #"""
        0024:0028:trace:loaddll:build_module Loaded L"C:\\Program Files (x86)\\Steam\\steam.exe" at 00400000: native
        0024:0028:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d11.dll" at 6FFFF0000000: builtin
        0030:0034:trace:loaddll:build_module Loaded L"C:\\Steam\\steamwebhelper.exe" at 140000000: native
        0030:0034:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d12.dll" at 6FFFE6ED0000: builtin
        0030:0034:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\wined3d.dll" at 6FFFE6BB0000: builtin
        0030:0034:trace:loaddll:free_modref Unloaded module L"C:\\windows\\system32\\d3d12.dll" : builtin
        0030:0034:trace:loaddll:free_modref Unloaded module L"C:\\windows\\system32\\wined3d.dll" : builtin
        0038:003c:trace:loaddll:build_module Loaded L"C:\\Steam\\steamwebhelper.exe" at 140000000: native
        0038:003c:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\d3d12.dll" at 6FFFE6ED0000: builtin
        0040:0044:trace:loaddll:build_module Loaded L"C:\\Games\\Old\\old.exe" at 00400000: native
        0040:0044:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\wined3d.dll" at 7B000000: builtin
        0050:0054:trace:loaddll:build_module Loaded L"C:\\Games\\New\\game.exe" at 00400000: native
        0050:0054:trace:loaddll:build_module Loaded L"C:\\Games\\New\\dxgi.dll" at 180000000: native
        err:   Failed to create metal view, it seems like your Wine has no exported symbols needed by DXMT.
        """#
        let fallbacks = GraphicsCheck.fallbacks(inLog: log)
        #expect(fallbacks.map(\.process) == ["old.exe", "game.exe", "DXMT"])
        #expect(fallbacks.map(\.what).prefix(2) == ["wined3d.dll", "dxgi.dll"])
    }

    @Test func flagsSteamSoftwareRendering() {
        let old = "[2026-10-30 10:00:00] Startup - webhelper launched pid: 1\n[2026-10-30 10:00:01] Disabling GPU acceleration due to --disable-gpu (browser)\n"
        let current = "[2026-10-30 11:00:00] Startup - webhelper launched pid: 2\n[2026-10-30 11:00:01] Starting message loop\n"
        #expect(GraphicsCheck.steamBrowserFallbacks(webhelperLog: old + current, cefLog: "").isEmpty)
        let fallback = GraphicsCheck.steamBrowserFallbacks(webhelperLog: old, cefLog: "")
        #expect(fallback.first?.what == "Disabling GPU acceleration due to --disable-gpu (browser)")
    }
}

struct RuntimeDXMTTests {
    @Test func refusesWithoutDXMT() throws {
        let fm = FileManager.default
        let dist = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: dist.appending(path: "wine/bin"), withIntermediateDirectories: true)
        try Data().write(to: dist.appending(path: "wine/bin/wine"))
        #expect(throws: NeutronError.self) { try Runtime.url(dist: dist, cache: dist.appending(path: "cache")) }
    }
}
