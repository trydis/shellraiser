import Foundation
import XCTest
@testable import Shellraiser

/// Covers filesystem-based Git branch resolution for workspace branch chips.
final class GitBranchResolverTests: XCTestCase {
    /// Verifies a standard repository resolves the checked-out branch from HEAD.
    func testGitStateReadsStandardGitDirectory() {
        let repositoryDirectory = makeDirectoryURL("/virtual/repo")
        let gitDirectory = repositoryDirectory.appendingPathComponent(".git", isDirectory: true)
        let resolver = makeResolver(
            entries: [
                repositoryDirectory: .directory,
                gitDirectory: .directory,
                gitDirectory.appendingPathComponent("HEAD"): .file("ref: refs/heads/main\n")
            ]
        )

        let gitState = resolver.resolveGitState(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "main", isLinkedWorktree: false))
    }

    /// Verifies repository discovery walks up from nested working directories.
    func testGitStateFindsRepositoryFromNestedDirectory() {
        let repositoryDirectory = makeDirectoryURL("/virtual/repo")
        let gitDirectory = repositoryDirectory.appendingPathComponent(".git", isDirectory: true)
        let nestedDirectory = repositoryDirectory
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Nested", isDirectory: true)
        let resolver = makeResolver(
            entries: [
                repositoryDirectory: .directory,
                nestedDirectory: .directory,
                gitDirectory: .directory,
                gitDirectory.appendingPathComponent("HEAD"): .file("ref: refs/heads/feature/nested\n")
            ]
        )

        let gitState = resolver.resolveGitState(forWorkingDirectory: nestedDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "feature/nested", isLinkedWorktree: false))
    }

    /// Verifies linked worktree `.git` indirection files resolve metadata and set the worktree flag.
    func testGitStateResolvesLinkedWorktreeGitFileIndirection() {
        let rootDirectory = makeDirectoryURL("/virtual/root")
        let repositoryDirectory = rootDirectory.appendingPathComponent("repo-worktree", isDirectory: true)
        let actualGitDirectory = rootDirectory
            .appendingPathComponent("main-repo", isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent("repo-worktree", isDirectory: true)
        let resolver = makeResolver(
            entries: [
                repositoryDirectory: .directory,
                repositoryDirectory.appendingPathComponent(".git"): .file("gitdir: ../main-repo/.git/worktrees/repo-worktree\n"),
                actualGitDirectory: .directory,
                actualGitDirectory.appendingPathComponent("HEAD"): .file("ref: refs/heads/worktree\n")
            ]
        )

        let gitState = resolver.resolveGitState(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "worktree", isLinkedWorktree: true))
    }

    /// Verifies submodule metadata indirection does not report a linked worktree.
    func testGitStateDoesNotMarkSubmoduleGitFileAsWorktree() {
        let rootDirectory = makeDirectoryURL("/virtual/root")
        let repositoryDirectory = rootDirectory.appendingPathComponent("submodule-checkout", isDirectory: true)
        let actualGitDirectory = rootDirectory
            .appendingPathComponent("main-repo", isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("modules", isDirectory: true)
            .appendingPathComponent("submodule-checkout", isDirectory: true)
        let resolver = makeResolver(
            entries: [
                repositoryDirectory: .directory,
                repositoryDirectory.appendingPathComponent(".git"): .file("gitdir: ../main-repo/.git/modules/submodule-checkout\n"),
                actualGitDirectory: .directory,
                actualGitDirectory.appendingPathComponent("HEAD"): .file("ref: refs/heads/submodule\n")
            ]
        )

        let gitState = resolver.resolveGitState(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "submodule", isLinkedWorktree: false))
    }

    /// Verifies detached HEAD state hides the branch text while preserving repository visibility.
    func testGitStateReturnsDetachedHeadWithoutBranchName() {
        let repositoryDirectory = makeDirectoryURL("/virtual/repo")
        let gitDirectory = repositoryDirectory.appendingPathComponent(".git", isDirectory: true)
        let resolver = makeResolver(
            entries: [
                repositoryDirectory: .directory,
                gitDirectory: .directory,
                gitDirectory.appendingPathComponent("HEAD"): .file("4f2ef7d6b9ac55f90f4cb1bc59b8c1c5d0adbeef\n")
            ]
        )

        let gitState = resolver.resolveGitState(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: nil, isLinkedWorktree: false))
    }

    /// Verifies directories outside Git repositories do not produce visible Git metadata.
    func testGitStateReturnsNilOutsideGitRepository() {
        let rootDirectory = makeDirectoryURL("/virtual/root")
        let directory = rootDirectory
            .appendingPathComponent("outside", isDirectory: true)
            .appendingPathComponent("repo", isDirectory: true)
        let resolver = makeResolver(entries: [directory: .directory], searchBoundaryURL: rootDirectory)

        let gitState = resolver.resolveGitState(forWorkingDirectory: directory.path)

        XCTAssertNil(gitState)
    }

    /// Creates a resolver backed by a synthetic in-memory filesystem.
    private func makeResolver(
        entries: [URL: MockGitResolverFileSystem.Entry],
        searchBoundaryURL: URL? = nil
    ) -> GitBranchResolver {
        GitBranchResolver(
            fileSystem: MockGitResolverFileSystem(entries: entries),
            searchBoundaryURL: searchBoundaryURL
        )
    }

    /// Creates a normalized directory URL for the synthetic filesystem.
    private func makeDirectoryURL(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// In-memory filesystem used to make Git resolver tests deterministic.
private struct MockGitResolverFileSystem: GitResolverFileSystem {
    /// Synthetic filesystem entry used by the mock implementation.
    enum Entry {
        case file(String)
        case directory
    }

    private let entriesByPath: [String: Entry]

    /// Creates a mock filesystem keyed by standardized URL path.
    init(entries: [URL: Entry]) {
        self.entriesByPath = Dictionary(
            uniqueKeysWithValues: entries.map { ($0.key.standardizedFileURL.path, $0.value) }
        )
    }

    /// Returns the synthetic entry type when present.
    func entryType(at url: URL) -> GitResolverFileSystemEntryType? {
        switch entriesByPath[url.standardizedFileURL.path] {
        case .file:
            return .file
        case .directory:
            return .directory
        case nil:
            return nil
        }
    }

    /// Returns synthetic file contents for mock text files.
    func readTextFile(at url: URL) -> String? {
        guard case .file(let contents) = entriesByPath[url.standardizedFileURL.path] else {
            return nil
        }

        return contents
    }
}
