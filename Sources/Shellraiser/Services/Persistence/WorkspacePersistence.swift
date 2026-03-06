import Foundation

/// Filesystem-backed persistence for workspace layout state.
final class WorkspacePersistence {
    private let fileManager = FileManager.default
    private let workspaceFileURL: URL

    /// Creates persistence rooted under Application Support.
    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupport.appendingPathComponent("Shellraiser", isDirectory: true)
        workspaceFileURL = appDirectory.appendingPathComponent("workspaces.json")
    }

    /// Loads serialized workspaces from disk.
    func load() -> [WorkspaceModel]? {
        guard fileManager.fileExists(atPath: workspaceFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: workspaceFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([WorkspaceModel].self, from: data)
        } catch {
            print("Failed to load workspaces: \(error)")
            return nil
        }
    }

    /// Persists workspaces atomically to avoid partial writes.
    func save(_ workspaces: [WorkspaceModel]) {
        do {
            try fileManager.createDirectory(
                at: workspaceFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(workspaces)

            try data.write(to: workspaceFileURL, options: .atomic)
        } catch {
            print("Failed to save workspaces: \(error)")
        }
    }
}
