import Foundation

/// Resolves the current Git branch for a working directory using repository metadata.
struct GitBranchResolver {
    private let fileManager: FileManager

    /// Creates a resolver with injectable filesystem access for testing.
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Returns the checked-out branch name for a working directory, or `nil` when unavailable.
    func branchName(forWorkingDirectory workingDirectory: String) -> String? {
        let trimmedPath = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let directoryURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        guard let gitMetadataURL = gitMetadataURL(startingAt: directoryURL),
              let headContents = readTextFile(at: gitMetadataURL.appendingPathComponent("HEAD")) else {
            return nil
        }

        let headLine = headContents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard headLine.hasPrefix("ref:") else { return nil }
        let reference = headLine
            .dropFirst("ref:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard reference.hasPrefix("refs/heads/") else { return nil }
        let branchName = String(reference.dropFirst("refs/heads/".count))
        return branchName.isEmpty ? nil : branchName
    }

    /// Walks up parent directories until Git metadata is found.
    private func gitMetadataURL(startingAt directoryURL: URL) -> URL? {
        var currentURL = normalizedDirectoryURL(for: directoryURL)

        while true {
            let gitURL = currentURL.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    return gitURL
                }

                return resolveGitFile(at: gitURL)
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else { return nil }
            currentURL = parentURL
        }
    }

    /// Normalizes a starting path into a directory URL even when the path points at a file.
    private func normalizedDirectoryURL(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        let path = url.path

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return url
        }

        return url.deletingLastPathComponent()
    }

    /// Resolves `.git` indirection files used by worktrees and submodules.
    private func resolveGitFile(at gitFileURL: URL) -> URL? {
        guard let contents = readTextFile(at: gitFileURL) else { return nil }

        let line = contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard line.hasPrefix("gitdir:") else { return nil }
        let gitDirectory = line
            .dropFirst("gitdir:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gitDirectory.isEmpty else { return nil }

        if gitDirectory.hasPrefix("/") {
            return URL(fileURLWithPath: gitDirectory, isDirectory: true)
        }

        return URL(fileURLWithPath: gitDirectory, relativeTo: gitFileURL.deletingLastPathComponent())
            .standardizedFileURL
    }

    /// Reads a UTF-8 text file and trims invalid or unreadable paths to `nil`.
    private func readTextFile(at fileURL: URL) -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }
}
