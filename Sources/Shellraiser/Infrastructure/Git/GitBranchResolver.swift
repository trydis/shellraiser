import Foundation

/// Filesystem entry kinds used while resolving Git metadata.
enum GitResolverFileSystemEntryType {
    case file
    case directory
}

/// Filesystem access required by the Git branch resolver.
protocol GitResolverFileSystem {
    /// Returns the entry type for a URL when it exists.
    func entryType(at url: URL) -> GitResolverFileSystemEntryType?

    /// Reads a UTF-8 text file from the provided URL.
    func readTextFile(at url: URL) -> String?
}

/// Resolved Git state for one working directory.
struct ResolvedGitState: Equatable {
    let branchName: String?
    let isLinkedWorktree: Bool

    /// Returns whether any Git metadata should be shown in the sidebar.
    var hasVisibleMetadata: Bool {
        branchName != nil || isLinkedWorktree
    }
}

/// Resolves visible Git metadata for a working directory using repository metadata.
struct GitBranchResolver {
    private let fileSystem: any GitResolverFileSystem
    private let searchBoundaryURL: URL?

    /// Creates a resolver with injectable filesystem access for testing.
    init(fileManager: FileManager = .default, searchBoundaryURL: URL? = nil) {
        self.init(
            fileSystem: LiveGitResolverFileSystem(fileManager: fileManager),
            searchBoundaryURL: searchBoundaryURL
        )
    }

    /// Creates a resolver with a custom filesystem implementation for tests.
    init(fileSystem: any GitResolverFileSystem, searchBoundaryURL: URL? = nil) {
        self.fileSystem = fileSystem
        self.searchBoundaryURL = searchBoundaryURL?.standardizedFileURL
    }

    /// Returns the visible Git state for a working directory, or `nil` when it is not inside a repository.
    func resolveGitState(forWorkingDirectory workingDirectory: String) -> ResolvedGitState? {
        let trimmedPath = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let directoryURL = URL(fileURLWithPath: trimmedPath, isDirectory: true)
        guard let repository = repositoryMetadata(startingAt: directoryURL),
              let headContents = readTextFile(at: repository.gitMetadataURL.appendingPathComponent("HEAD")) else {
            return nil
        }

        let headLine = headContents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let branchName: String? = {
            guard headLine.hasPrefix("ref:") else { return nil }
            let reference = headLine
                .dropFirst("ref:".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard reference.hasPrefix("refs/heads/") else { return nil }
            let branchName = String(reference.dropFirst("refs/heads/".count))
            return branchName.isEmpty ? nil : branchName
        }()

        return ResolvedGitState(
            branchName: branchName,
            isLinkedWorktree: repository.isLinkedWorktree
        )
    }

    /// Returns the checked-out branch name for a working directory, or `nil` when unavailable.
    func branchName(forWorkingDirectory workingDirectory: String) -> String? {
        resolveGitState(forWorkingDirectory: workingDirectory)?.branchName
    }

    /// Repository metadata derived from `.git` discovery.
    private struct RepositoryMetadata {
        let gitMetadataURL: URL
        let isLinkedWorktree: Bool
    }

    /// Walks up parent directories until Git metadata is found.
    private func repositoryMetadata(startingAt directoryURL: URL) -> RepositoryMetadata? {
        var currentURL = normalizedDirectoryURL(for: directoryURL)
        let boundaryPath = searchBoundaryURL?.path

        while true {
            let gitURL = currentURL.appendingPathComponent(".git")
            if let entryType = fileSystem.entryType(at: gitURL) {
                if entryType == .directory {
                    return RepositoryMetadata(gitMetadataURL: gitURL, isLinkedWorktree: false)
                }

                return resolveGitFile(at: gitURL)
            }

            if currentURL.standardizedFileURL.path == boundaryPath {
                return nil
            }

            let parentURL = currentURL.deletingLastPathComponent()
            guard parentURL.path != currentURL.path else { return nil }
            currentURL = parentURL
        }
    }

    /// Normalizes a starting path into a directory URL even when the path points at a file.
    private func normalizedDirectoryURL(for url: URL) -> URL {
        guard fileSystem.entryType(at: url) == .file else { return url }
        return url.deletingLastPathComponent()
    }

    /// Resolves `.git` indirection files used by worktrees and submodules.
    private func resolveGitFile(at gitFileURL: URL) -> RepositoryMetadata? {
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
            let resolvedURL = URL(fileURLWithPath: gitDirectory, isDirectory: true)
            return RepositoryMetadata(
                gitMetadataURL: resolvedURL,
                isLinkedWorktree: isLinkedWorktreeDirectory(resolvedURL)
            )
        }

        let resolvedURL = URL(fileURLWithPath: gitDirectory, relativeTo: gitFileURL.deletingLastPathComponent())
            .standardizedFileURL
        return RepositoryMetadata(
            gitMetadataURL: resolvedURL,
            isLinkedWorktree: isLinkedWorktreeDirectory(resolvedURL)
        )
    }

    /// Returns whether a resolved gitdir belongs to a linked `git worktree` checkout.
    private func isLinkedWorktreeDirectory(_ gitMetadataURL: URL) -> Bool {
        let pathComponents = gitMetadataURL.standardizedFileURL.pathComponents
        guard let gitIndex = pathComponents.lastIndex(of: ".git"),
              gitIndex + 1 < pathComponents.count else {
            return false
        }

        return pathComponents[gitIndex + 1] == "worktrees"
    }

    /// Reads a UTF-8 text file and trims invalid or unreadable paths to `nil`.
    private func readTextFile(at fileURL: URL) -> String? {
        fileSystem.readTextFile(at: fileURL)
    }
}

/// Live filesystem adapter backed by Foundation file APIs.
private struct LiveGitResolverFileSystem: GitResolverFileSystem {
    private let fileManager: FileManager

    /// Creates a live filesystem adapter from a `FileManager`.
    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    /// Returns the entry type for a URL when it exists on disk.
    func entryType(at url: URL) -> GitResolverFileSystemEntryType? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        return isDirectory.boolValue ? .directory : .file
    }

    /// Reads UTF-8 text contents from disk when the file is available.
    func readTextFile(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
