import Foundation

/// Neutron renders only with DXMT. This finds processes that loaded something else, from the `+pid,+loaddll` trace
/// Wine writes for Steam and every game Steam starts.
public enum GraphicsCheck {
    public struct Fallback: Hashable, Sendable, CustomStringConvertible {
        public let process: String
        public let library: String
        public let reason: String

        public var description: String { "\(process) loaded \(library): \(reason)" }
    }

    static let dxmtLibraries: Set<String> = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"]

    static func reason(library: String, native: Bool) -> String? {
        switch library {
        case "wined3d.dll": "Wine's wined3d (OpenGL) instead of DXMT"
        case "d3d12.dll", "d3d12core.dll": native ? "the program's own Direct3D 12, not DXMT" : "Wine's Direct3D 12 (vkd3d), not DXMT"
        case _ where library.contains("swiftshader"): "Chromium's software renderer instead of DXMT"
        case _ where dxmtLibraries.contains(library) && native: "the program's own \(library) instead of DXMT's"
        default: nil
        }
    }

    /// Lines look like `0024:0130:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\wined3d.dll" at 00006FFFF7A40000: builtin`.
    public static func fallbacks(inLog text: String) -> [Fallback] {
        var processes: [String: String] = [:]
        var result: [Fallback] = []
        var seen = Set<Fallback>()
        for line in text.split(whereSeparator: \.isNewline) where line.contains(":loaddll:") {
            guard let quoteStart = line.range(of: "L\""),
                  let quoteEnd = line[quoteStart.upperBound...].firstIndex(of: "\"") else { continue }
            let pid = String(line.prefix { $0 != ":" })
            let path = line[quoteStart.upperBound..<quoteEnd].replacingOccurrences(of: "\\\\", with: "\\")
            let library = String(path.split(separator: "\\").last ?? "").lowercased()
            if library.hasSuffix(".exe"), processes[pid] == nil {
                processes[pid] = library
                continue
            }
            let native = line.hasSuffix(": native")
            guard let reason = reason(library: library, native: native) else { continue }
            let fallback = Fallback(process: processes[pid] ?? "process \(pid)", library: library, reason: reason)
            if seen.insert(fallback).inserted { result.append(fallback) }
        }
        return result
    }
}
