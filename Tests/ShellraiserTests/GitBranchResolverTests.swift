import Foundation
import XCTest
@testable import Shellraiser

/// Covers filesystem-based Git branch resolution for workspace branch chips.
final class GitBranchResolverTests: XCTestCase {
    /// Verifies a standard repository resolves the checked-out branch from HEAD.
    func testGitStateReadsStandardGitDirectory() throws {
        let context = try makeRepositoryContext()
        try writeText("ref: refs/heads/main\n", to: context.gitDirectory.appendingPathComponent("HEAD"))

        let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: context.repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "main", isLinkedWorktree: false))
    }

    /// Verifies repository discovery walks up from nested working directories.
    func testGitStateFindsRepositoryFromNestedDirectory() throws {
        let context = try makeRepositoryContext()
        let nestedDirectory = context.repositoryDirectory
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try writeText("ref: refs/heads/feature/nested\n", to: context.gitDirectory.appendingPathComponent("HEAD"))

        let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: nestedDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "feature/nested", isLinkedWorktree: false))
    }

    /// Verifies linked worktree `.git` indirection files resolve metadata and set the worktree flag.
    func testGitStateResolvesLinkedWorktreeGitFileIndirection() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositoryDirectory = rootDirectory.appendingPathComponent("repo-worktree", isDirectory: true)
        let actualGitDirectory = rootDirectory
            .appendingPathComponent("main-repo", isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("worktrees", isDirectory: true)
            .appendingPathComponent("repo-worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: actualGitDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        try writeText("gitdir: ../main-repo/.git/worktrees/repo-worktree\n", to: repositoryDirectory.appendingPathComponent(".git"))
        try writeText("ref: refs/heads/worktree\n", to: actualGitDirectory.appendingPathComponent("HEAD"))

        let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "worktree", isLinkedWorktree: true))
    }

    /// Verifies submodule metadata indirection does not report a linked worktree.
    func testGitStateDoesNotMarkSubmoduleGitFileAsWorktree() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositoryDirectory = rootDirectory.appendingPathComponent("submodule-checkout", isDirectory: true)
        let actualGitDirectory = rootDirectory
            .appendingPathComponent("main-repo", isDirectory: true)
            .appendingPathComponent(".git", isDirectory: true)
            .appendingPathComponent("modules", isDirectory: true)
            .appendingPathComponent("submodule-checkout", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: actualGitDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        try writeText("gitdir: ../main-repo/.git/modules/submodule-checkout\n", to: repositoryDirectory.appendingPathComponent(".git"))
        try writeText("ref: refs/heads/submodule\n", to: actualGitDirectory.appendingPathComponent("HEAD"))

        let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: "submodule", isLinkedWorktree: false))
    }

    /// Verifies detached HEAD state hides the branch text while preserving repository visibility.
    func testGitStateReturnsDetachedHeadWithoutBranchName() throws {
        let context = try makeRepositoryContext()
        try writeText("4f2ef7d6b9ac55f90f4cb1bc59b8c1c5d0adbeef\n", to: context.gitDirectory.appendingPathComponent("HEAD"))

        let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: context.repositoryDirectory.path)

        XCTAssertEqual(gitState, ResolvedGitState(branchName: nil, isLinkedWorktree: false))
    }

    /// Verifies directories outside Git repositories do not produce visible Git metadata.
    func testGitStateReturnsNilOutsideGitRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: directory.path)

        XCTAssertNil(gitState)
    }

    /// Creates a disposable repository directory with a `.git` folder.
    private func makeRepositoryContext() throws -> (repositoryDirectory: URL, gitDirectory: URL) {
        let repositoryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let gitDirectory = repositoryDirectory.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: repositoryDirectory)
        }
        return (repositoryDirectory, gitDirectory)
    }

    /// Writes plain UTF-8 text into a file, creating parent directories if needed.
    private func writeText(_ text: String, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
