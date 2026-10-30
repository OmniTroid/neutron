import Foundation

/// Neutron renders only with DXMT. This finds processes that render with something else, from the `+pid,+loaddll`
/// trace Wine writes for Steam and every game Steam starts, and from Steam's own browser logs.
public enum GraphicsCheck {
    public struct Fallback: Hashable, Sendable, CustomStringConvertible {
        public let process: String
        public let what: String
        public let reason: String

        public var description: String { "\(process): \(what): \(reason)" }
    }

    static let dxmtLibraries: Set<String> = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"]

    static func reason(library: String, native: Bool) -> String? {
        switch library {
        case "wined3d.dll": "Wine's wined3d (OpenGL) instead of DXMT"
        case "d3d12.dll", "d3d12core.dll": native ? "the program's own Direct3D 12, not DXMT" : "Wine's Direct3D 12 (vkd3d), not DXMT"
        case _ where dxmtLibraries.contains(library) && native: "the program's own \(library) instead of DXMT's"
        default: nil
        }
    }

    /// Libraries a process still holds. One loaded and then unloaded was a capability probe, as Chromium does with
    /// Direct3D 12 at startup; a renderer stays loaded until the process exits, which Wine doesn't trace as an unload.
    /// Lines look like `0024:0130:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\wined3d.dll" at 00006FFFF7A40000: builtin`
    /// and `0024:0130:trace:loaddll:free_modref Unloaded module L"C:\\windows\\system32\\wined3d.dll" : builtin`.
    public static func fallbacks(inLog text: String) -> [Fallback] {
        var processes: [String: String] = [:]
        var held: [Fallback] = []
        for line in text.split(whereSeparator: \.isNewline) {
            // DXMT's own errors carry no process id
            if line.hasPrefix("err:"), line.contains("Failed to create metal view") || line.contains("Failed to get metal layer") {
                held.append(Fallback(process: "DXMT", what: line.dropFirst(4).trimmingCharacters(in: .whitespaces),
                                     reason: "DXMT couldn't present to the window, so it shows nothing or falls back"))
                continue
            }
            guard line.contains(":loaddll:") else { continue }
            guard let quoteStart = line.range(of: "L\""),
                  let quoteEnd = line[quoteStart.upperBound...].firstIndex(of: "\"") else { continue }
            let pid = String(line.prefix { $0 != ":" })
            let path = line[quoteStart.upperBound..<quoteEnd].replacingOccurrences(of: "\\\\", with: "\\")
            let library = String(path.split(separator: "\\").last ?? "").lowercased()
            if library.hasSuffix(".exe"), processes[pid] == nil {
                processes[pid] = library
                continue
            }
            // Chromium's GPU info process probes Direct3D 12 and exits; Steam's fallback shows in its own logs instead
            guard processes[pid] != "steamwebhelper.exe",
                  let reason = reason(library: library, native: line.hasSuffix(": native")) else { continue }
            let fallback = Fallback(process: processes[pid] ?? "process \(pid)", what: library, reason: reason)
            if line.contains("Unloaded module") {
                if let index = held.lastIndex(of: fallback) { held.remove(at: index) }
            } else {
                held.append(fallback)
            }
        }
        var seen = Set<Fallback>()
        return held.filter { seen.insert($0).inserted }
    }

    /// Steam's browser falling back to software rendering, from the client's `logs/webhelper.txt` and `cef_log.txt`.
    public static func steamBrowserFallbacks(webhelperLog: String, cefLog: String) -> [Fallback] {
        let markers = ["Disabling GPU acceleration", "GPU process isn't usable", "Exiting GPU process due to errors"]
        // both logs keep earlier starts; only the latest counts
        let webhelper = webhelperLog.components(separatedBy: "Startup - webhelper launched").last ?? ""
        let cef = cefLog.components(separatedBy: "This is Chrome version").last ?? ""
        let lines = webhelper.split(whereSeparator: \.isNewline) + cef.split(whereSeparator: \.isNewline)
        guard let line = lines.first(where: { line in markers.contains { line.contains($0) } }) else { return [] }
        let detail = line.drop { $0 != "]" }.dropFirst().trimmingCharacters(in: .whitespaces)
        return [Fallback(process: "steamwebhelper.exe", what: detail, reason: "Steam's browser renders in software instead of DXMT")]
    }
}
