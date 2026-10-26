import Foundation

/// A Valve KeyValues node. Objects keep their key order.
public indirect enum KeyValue: Equatable, Sendable {
    case object([(key: String, value: KeyValue)])
    case string(String)
    case int(Int64)
    case float(Float)

    public subscript(key: String) -> KeyValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

    public var children: [(key: String, value: KeyValue)] {
        if case .object(let pairs) = self { return pairs }
        return []
    }

    /// Strings as-is, numbers formatted; Steam stores some fields (e.g. osarch) as either.
    public var text: String? {
        switch self {
        case .string(let s): s
        case .int(let i): String(i)
        case .float(let f): String(f)
        case .object: nil
        }
    }

    public static func == (lhs: KeyValue, rhs: KeyValue) -> Bool {
        switch (lhs, rhs) {
        case (.object(let a), .object(let b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case (.string(let a), .string(let b)): a == b
        case (.int(let a), .int(let b)): a == b
        case (.float(let a), .float(let b)): a == b
        default: false
        }
    }
}

private struct Reader {
    let bytes: [UInt8]
    var pos: Int

    mutating func u8() throws -> UInt8 {
        guard pos < bytes.count else { throw NeutronError("appinfo.vdf truncated") }
        defer { pos += 1 }
        return bytes[pos]
    }

    mutating func int<T: FixedWidthInteger>(_: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard pos + size <= bytes.count else { throw NeutronError("appinfo.vdf truncated") }
        defer { pos += size }
        return bytes.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: pos, as: T.self)) }
    }

    mutating func cString() throws -> String {
        guard let end = bytes[pos...].firstIndex(of: 0) else { throw NeutronError("appinfo.vdf truncated") }
        defer { pos = end + 1 }
        return String(decoding: bytes[pos..<end], as: UTF8.self)
    }

    /// Binary KeyValues; keys are string-table indices when `strings` is given (appinfo v29).
    mutating func object(strings: [String]?) throws -> KeyValue {
        var pairs: [(key: String, value: KeyValue)] = []
        while true {
            let kind = try u8()
            if kind == 0x08 { return .object(pairs) }
            let key: String
            if let strings {
                let index = Int(try int(UInt32.self))
                guard index < strings.count else { throw NeutronError("appinfo.vdf bad string index") }
                key = strings[index]
            } else {
                key = try cString()
            }
            switch kind {
            case 0x00: pairs.append((key, try object(strings: strings)))
            case 0x01: pairs.append((key, .string(try cString())))
            case 0x02, 0x04, 0x06: pairs.append((key, .int(Int64(try int(Int32.self)))))
            case 0x03: pairs.append((key, .float(Float(bitPattern: try int(UInt32.self)))))
            case 0x07, 0x0A: pairs.append((key, .int(try int(Int64.self))))
            default: throw NeutronError("appinfo.vdf unknown KeyValues type \(kind)")
            }
        }
    }
}

public enum AppInfo {
    /// Reads one app from the Steam client's appinfo.vdf cache (v28 or v29); nil if Steam hasn't cached it.
    public static func read(appID: UInt32, from url: URL = Paths.steamAppInfo) throws -> KeyValue? {
        try entries(from: url, only: appID)[appID]
    }

    /// Every app in the Steam client's appinfo.vdf cache.
    public static func all(from url: URL = Paths.steamAppInfo) throws -> [UInt32: KeyValue] {
        try entries(from: url, only: nil)
    }

    private static func entries(from url: URL, only wanted: UInt32?) throws -> [UInt32: KeyValue] {
        var reader = Reader(bytes: [UInt8](try Data(contentsOf: url)), pos: 0)
        let magic = try reader.int(UInt32.self)
        _ = try reader.int(UInt32.self)

        var strings: [String]?
        switch magic {
        case 0x0756_4429:
            let tableOffset = Int(try reader.int(Int64.self))
            var table = Reader(bytes: reader.bytes, pos: tableOffset)
            strings = try (0..<table.int(UInt32.self)).map { _ in try table.cString() }
        case 0x0756_4428:
            strings = nil
        default:
            throw NeutronError("unsupported appinfo.vdf version \(String(magic, radix: 16))")
        }

        var result: [UInt32: KeyValue] = [:]
        while true {
            let id = try reader.int(UInt32.self)
            if id == 0 { return result }
            let size = Int(try reader.int(UInt32.self))
            let next = reader.pos + size
            if wanted == nil || id == wanted {
                // skip info state, last updated, PICS token, text SHA-1, change number, binary SHA-1
                reader.pos += 60
                let info = try reader.object(strings: strings)
                result[id] = info["appinfo"] ?? info
                if wanted != nil { return result }
            }
            reader.pos = next
        }
    }

    /// App IDs covered by the packages (licenses) cached in the Steam client's packageinfo.vdf.
    public static func ownedAppIDs(from url: URL = Paths.steamPackageInfo) throws -> Set<UInt32> {
        var reader = Reader(bytes: [UInt8](try Data(contentsOf: url)), pos: 0)
        let magic = try reader.int(UInt32.self)
        _ = try reader.int(UInt32.self)
        guard magic == 0x0656_5528 || magic == 0x0656_5527 else {
            throw NeutronError("unsupported packageinfo.vdf version \(String(magic, radix: 16))")
        }

        var apps = Set<UInt32>()
        while try reader.int(UInt32.self) != 0xFFFF_FFFF {
            // skip SHA-1, change number and (v28) PICS token
            reader.pos += 24 + (magic == 0x0656_5528 ? 8 : 0)
            for (_, package) in try reader.object(strings: nil).children {
                for (_, app) in package["appids"]?.children ?? [] {
                    if case .int(let id) = app { apps.insert(UInt32(truncatingIfNeeded: id)) }
                }
            }
        }
        return apps
    }

    /// The Windows launch option to use: the default one, else a Direct3D 11 alternative (what DXMT runs),
    /// else the first alternative; 64-bit preferred throughout.
    public static func windowsLaunch(_ appInfo: KeyValue) -> KeyValue? {
        let entries = (appInfo["config"]?["launch"]?.children ?? [])
            .sorted { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }
            .map(\.value)
            .filter { entry in
                let config = entry["config"]
                let type = entry["type"]?.text ?? "default"
                return entry["executable"]?.text != nil
                    && (config?["oslist"]?.text ?? "windows").contains("windows")
                    && (["default", "none"].contains(type) || type.hasPrefix("option"))
                    && config?["betakey"] == nil
            }

        func rank(_ entry: KeyValue) -> Int {
            let type = entry["type"]?.text ?? "default"
            let text = [entry["description"]?.text, entry["arguments"]?.text].compactMap { $0 }.joined(separator: " ")
            let isD3D11 = text.range(of: #"d3d11|dx11|directx ?11"#, options: [.regularExpression, .caseInsensitive]) != nil
            let kind = ["default", "none"].contains(type) ? 0 : isD3D11 ? 1 : 2
            return kind * 2 + (entry["config"]?["osarch"]?.text == "64" ? 0 : 1)
        }
        return entries.enumerated().min { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }?.element
    }

    /// Bytes on disk for the depots a Windows install downloads: matching OS, architecture and
    /// language, skipping low-violence and DLC depots; nil if Steam lists no sizes.
    public static func windowsInstallSize(_ appInfo: KeyValue, is64Bit: Bool) -> Int64? {
        var total: Int64 = 0
        var found = false
        for (_, depot) in appInfo["depots"]?.children ?? [] {
            guard let size = depot["manifests"]?["public"]?["size"]?.text.flatMap({ Int64($0) }) else { continue }
            let config = depot["config"]
            let oslist = config?["oslist"]?.text ?? ""
            let osarch = config?["osarch"]?.text ?? ""
            let language = config?["language"]?.text ?? ""
            guard oslist.isEmpty || oslist.contains("windows"),
                  osarch.isEmpty || osarch == (is64Bit ? "64" : "32"),
                  language.isEmpty || language == "english",
                  config?["lowviolence"] == nil,
                  depot["dlcappid"] == nil else { continue }
            total += size
            found = true
        }
        return found ? total : nil
    }
}
