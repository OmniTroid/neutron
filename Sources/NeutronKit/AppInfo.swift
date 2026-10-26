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

        while true {
            let id = try reader.int(UInt32.self)
            if id == 0 { return nil }
            let size = Int(try reader.int(UInt32.self))
            let next = reader.pos + size
            if id == appID {
                // skip info state, last updated, PICS token, text SHA-1, change number, binary SHA-1
                reader.pos += 60
                let info = try reader.object(strings: strings)
                return info["appinfo"] ?? info
            }
            reader.pos = next
        }
    }

    /// The launch option Steam would use on Windows, preferring 64-bit.
    public static func windowsLaunch(_ appInfo: KeyValue) -> KeyValue? {
        let entries = (appInfo["config"]?["launch"]?.children ?? [])
            .sorted { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }
            .map(\.value)
            .filter { entry in
                let config = entry["config"]
                return entry["executable"]?.text != nil
                    && (config?["oslist"]?.text ?? "windows").contains("windows")
                    && ["default", "none"].contains(entry["type"]?.text ?? "default")
                    && config?["betakey"] == nil
            }
        return entries.first { $0["config"]?["osarch"]?.text == "64" } ?? entries.first
    }
}
