import Foundation

/// Per-game compatibility notes from highball-db, generated into data/compat.json by scripts/update-compat-db.sh.
public struct CompatDB: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public struct AntiCheat: Decodable, Sendable {
            public var names: [String]?
            public var macVerdict: String?
        }

        public var title: String
        public var status: String
        public var renderer: String?
        public var launchArgs: [String]?
        public var anticheat: AntiCheat?
        public var nativeMac: Bool?
        public var lastVerified: String?
        public var summary: String?

        public var blocked: Bool {
            status.hasPrefix("blocked") || anticheat?.macVerdict == "blocked"
        }

        public var usesVAC: Bool { anticheat?.names?.contains("VAC") ?? false }

        /// Only entries someone ran; anti-cheat-only rows carry no playability verdict.
        public var tested: Bool { status != "anticheat-only" }
    }

    public var source: String
    public var license: String
    public var games: [String: Entry]

    public static let shared: CompatDB? = Paths.data().flatMap { try? load(from: $0.appending(path: "compat.json")) }

    public static func load(from url: URL) throws -> CompatDB {
        try JSONDecoder().decode(CompatDB.self, from: Data(contentsOf: url))
    }

    public func entry(appID: UInt32) -> Entry? { games[String(appID)] }
}
