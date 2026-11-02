import Foundation

/// Windows programs started through Neutron, newest first, for starting again.
public struct RecentPrograms: Sendable {
    static let limit = 20
    let file: URL

    public init(file: URL = Paths.recentPrograms) {
        self.file = file
    }

    /// The ones still on disk.
    public func load() -> [URL] {
        stored().filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func record(_ program: URL) {
        guard !Self.isInstaller(program) else { return }
        save([program] + stored().filter { $0.path != program.path })
    }

    public func remove(_ program: URL) {
        save(stored().filter { $0.path != program.path })
    }

    static func isInstaller(_ program: URL) -> Bool {
        let name = program.lastPathComponent.lowercased()
        return ["setup", "install", "unins"].contains { name.contains($0) }
    }

    private func stored() -> [URL] {
        guard let data = try? Data(contentsOf: file),
              let paths = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return paths.map { URL(filePath: $0) }
    }

    private func save(_ programs: [URL]) {
        guard let data = try? JSONEncoder().encode(programs.prefix(Self.limit).map(\.path)) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}
