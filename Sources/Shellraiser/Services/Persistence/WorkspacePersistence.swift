import Foundation

/// Persistence interface used by workspace services and tests.
protocol WorkspacePersisting {
    /// Loads serialized workspaces from storage.
    func load() -> [WorkspaceModel]?

    /// Persists workspaces to storage.
    func save(_ workspaces: [WorkspaceModel])
}

/// Filesystem-backed persistence for workspace layout state.
final class WorkspacePersistence: WorkspacePersisting {
    /// Environment variable used to force a dedicated Application Support subdirectory.
    static let appSupportSubdirectoryEnvironmentKey = "SHELLRAISER_APP_SUPPORT_SUBDIRECTORY"

    /// Environment variable used to suppress persistence error logs during tests.
    static let suppressErrorLoggingEnvironmentKey = "SHELLRAISER_SUPPRESS_PERSISTENCE_ERRORS"

    private let fileManager = FileManager.default
    private let logsErrors: Bool
    private let workspaceFileURL: URL

    /// Returns the directory containing the persisted workspace file.
    var directoryURL: URL {
        workspaceFileURL.deletingLastPathComponent()
    }

    /// Creates persistence rooted under Application Support.
    convenience init() {
        self.init(
            directoryURL: Self.defaultDirectoryURL(fileManager: .default)
        )
    }

    /// Creates persistence rooted under an explicit directory.
    init(directoryURL: URL, logsErrors: Bool? = nil) {
        self.logsErrors = logsErrors ?? Self.shouldLogErrors
        workspaceFileURL = directoryURL.appendingPathComponent("workspaces.json")
    }

    /// Resolves the default persistence directory for the current app instance.
    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(
            appSupportSubdirectory(),
            isDirectory: true
        )
    }

    /// Resolves the Application Support subdirectory for the current app instance.
    private static func appSupportSubdirectory() -> String {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment[appSupportSubdirectoryEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           let validatedOverride = validatedAppSupportSubdirectory(override) {
            return validatedOverride
        }

        let defaultBundleIdentifier = "com.shellraiser.app"
        if shouldUseBundleSpecificAppSupportSubdirectory,
           let bundleIdentifier = Bundle.main.bundleIdentifier,
           bundleIdentifier != defaultBundleIdentifier {
            return sanitizedAppSupportSubdirectory(for: bundleIdentifier)
        }

        return "Shellraiser"
    }

    /// Validates that an override is a single safe Application Support path component.
    private static func validatedAppSupportSubdirectory(_ override: String) -> String? {
        guard !override.isEmpty else {
            return nil
        }

        guard !override.contains("/"), !override.contains("\\") else {
            return nil
        }

        guard override != ".", override != ".." else {
            return nil
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "._-")
        )
        guard override.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return nil
        }

        return override
    }

    /// Produces a filesystem-friendly Application Support subdirectory name.
    private static func sanitizedAppSupportSubdirectory(for bundleIdentifier: String) -> String {
        let sanitizedIdentifier = bundleIdentifier.map { character in
            character.isLetter || character.isNumber ? character : "-"
        }
        return "Shellraiser-\(String(sanitizedIdentifier))"
    }

    /// Returns whether the current process is a packaged app bundle.
    private static var shouldUseBundleSpecificAppSupportSubdirectory: Bool {
        guard let packageType = Bundle.main.object(
            forInfoDictionaryKey: "CFBundlePackageType"
        ) as? String else {
            return false
        }

        return packageType == "APPL" && Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Returns whether persistence failures should be logged for the current process.
    private static var shouldLogErrors: Bool {
        let rawValue = ProcessInfo.processInfo.environment[suppressErrorLoggingEnvironmentKey] ?? ""
        return !["1", "true", "yes", "on"].contains(rawValue.lowercased())
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
            if logsErrors {
                print("Failed to load workspaces: \(error)")
            }
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
            if logsErrors {
                print("Failed to save workspaces: \(error)")
            }
        }
    }
}
