import Foundation

extension KeyValue {
    /// Text KeyValues, as in Steam's .vdf and .acf files.
    public static func parse(text: String) throws -> KeyValue {
        var scanner = TextScanner(chars: Array(text), pos: 0)
        return .object(try scanner.pairs(nested: false))
    }
}

private struct TextScanner {
    let chars: [Character]
    var pos: Int

    mutating func pairs(nested: Bool) throws -> [(key: String, value: KeyValue)] {
        var result: [(key: String, value: KeyValue)] = []
        while let token = try next() {
            if token == "}" {
                guard nested else { throw NeutronError("unbalanced } in KeyValues") }
                return result
            }
            guard let value = try next() else { throw NeutronError("KeyValues ends after key \(token)") }
            result.append((token, value == "{" ? .object(try pairs(nested: true)) : .string(value)))
        }
        if nested { throw NeutronError("KeyValues ends inside an object") }
        return result
    }

    /// The next quoted or bare token, or a brace; nil at the end.
    mutating func next() throws -> String? {
        while pos < chars.count {
            let c = chars[pos]
            if c.isWhitespace {
                pos += 1
            } else if c == "/", pos + 1 < chars.count, chars[pos + 1] == "/" {
                while pos < chars.count, !chars[pos].isNewline { pos += 1 }
            } else {
                break
            }
        }
        guard pos < chars.count else { return nil }
        if chars[pos] == "{" || chars[pos] == "}" {
            defer { pos += 1 }
            return String(chars[pos])
        }
        var token = ""
        if chars[pos] == "\"" {
            pos += 1
            while pos < chars.count, chars[pos] != "\"" {
                if chars[pos] == "\\", pos + 1 < chars.count {
                    pos += 1
                    token.append(["n": "\n", "t": "\t"][chars[pos]] ?? chars[pos])
                } else {
                    token.append(chars[pos])
                }
                pos += 1
            }
            guard pos < chars.count else { throw NeutronError("unterminated string in KeyValues") }
            pos += 1
        } else {
            while pos < chars.count, !chars[pos].isWhitespace, !"{}\"".contains(chars[pos]) {
                token.append(chars[pos])
                pos += 1
            }
        }
        return token
    }
}

/// An app's install state, from the Windows client's appmanifest_<appid>.acf.
public struct AppState: Sendable, Equatable {
    public var installed: Bool
    public var updating: Bool
    public var paused: Bool
    public var bytesDownloaded: Int64
    public var bytesToDownload: Int64
    public var sizeOnDisk: Int64
    public var directory: URL

    public var progress: Double? {
        bytesToDownload > 0 ? Double(bytesDownloaded) / Double(bytesToDownload) : nil
    }

    // EAppState flags
    static let fullyInstalled = 4
    static let updatePaused = 512
    static let busy = 256 | 1024 | 524_288 | 1_048_576 | 2_097_152 | 4_194_304

    init?(manifest: KeyValue, steamapps: URL) {
        let state = manifest["AppState"] ?? manifest
        guard let flags = state["StateFlags"]?.text.flatMap(Int.init), let dir = state["installdir"]?.text else { return nil }
        func number(_ key: String) -> Int64 { state[key]?.text.flatMap { Int64($0) } ?? 0 }
        installed = flags & AppState.fullyInstalled != 0
        updating = flags & AppState.busy != 0
        paused = flags & AppState.updatePaused != 0
        bytesDownloaded = number("BytesDownloaded")
        bytesToDownload = number("BytesToDownload")
        sizeOnDisk = number("SizeOnDisk")
        directory = steamapps.appending(path: "common/\(dir)")
    }
}

public enum SteamApps {
    /// Install state of every app the client has a manifest for, across its library folders.
    public static func states(steam: URL = Paths.steam, prefix: URL = Paths.steamPrefix) -> [UInt32: AppState] {
        var result: [UInt32: AppState] = [:]
        for steamapps in libraryFolders(steam: steam, prefix: prefix) {
            let files = (try? FileManager.default.contentsOfDirectory(atPath: steamapps.path)) ?? []
            for file in files where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                guard let appID = UInt32(file.dropFirst("appmanifest_".count).dropLast(".acf".count)),
                      let text = try? String(contentsOf: steamapps.appending(path: file), encoding: .utf8),
                      let manifest = try? KeyValue.parse(text: text),
                      let state = AppState(manifest: manifest, steamapps: steamapps) else { continue }
                result[appID] = state
            }
        }
        return result
    }

    /// The `steamapps` folders listed in libraryfolders.vdf, with Windows paths mapped into the prefix.
    static func libraryFolders(steam: URL, prefix: URL) -> [URL] {
        let main = steam.appending(path: "steamapps")
        guard let text = try? String(contentsOf: main.appending(path: "libraryfolders.vdf"), encoding: .utf8),
              let vdf = try? KeyValue.parse(text: text) else { return [main] }
        let folders = (vdf["libraryfolders"]?.children ?? []).compactMap { $0.value["path"]?.text }
            .compactMap { macPath(windows: $0, prefix: prefix)?.appending(path: "steamapps") }
        return folders.isEmpty ? [main] : folders
    }

    /// `C:\Program Files (x86)\Steam` → the matching path under the prefix's dosdevices.
    static func macPath(windows path: String, prefix: URL) -> URL? {
        guard path.count >= 2, path.dropFirst().first == ":" else { return nil }
        let drive = prefix.appending(path: "dosdevices/\(path.prefix(2).lowercased())").resolvingSymlinksInPath()
        let rest = path.dropFirst(2).split(whereSeparator: { $0 == "\\" || $0 == "/" }).joined(separator: "/")
        return rest.isEmpty ? drive : drive.appending(path: rest)
    }
}
