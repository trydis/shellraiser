import Foundation
import XCTest
@testable import Shellraiser

/// Covers filesystem-based Git branch resolution for workspace branch chips.
final class GitBranchResolverTests: XCTestCase {
    /// Verifies a standard repository resolves the checked-out branch from HEAD.
    func testBranchNameReadsStandardGitDirectory() throws {
        let context = try makeRepositoryContext()
        try writeText("ref: refs/heads/main\n", to: context.gitDirectory.appendingPathComponent("HEAD"))

        let branchName = GitBranchResolver().branchName(forWorkingDirectory: context.repositoryDirectory.path)

        XCTAssertEqual(branchName, "main")
    }

    /// Verifies repository discovery walks up from nested working directories.
    func testBranchNameFindsRepositoryFromNestedDirectory() throws {
        let context = try makeRepositoryContext()
        let nestedDirectory = context.repositoryDirectory
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try writeText("ref: refs/heads/feature/nested\n", to: context.gitDirectory.appendingPathComponent("HEAD"))

        let branchName = GitBranchResolver().branchName(forWorkingDirectory: nestedDirectory.path)

        XCTAssertEqual(branchName, "feature/nested")
    }

    /// Verifies worktree-style `.git` indirection files resolve to the actual metadata directory.
    func testBranchNameResolvesGitFileIndirection() throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repositoryDirectory = rootDirectory.appendingPathComponent("repo", isDirectory: true)
        let actualGitDirectory = rootDirectory.appendingPathComponent("metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: actualGitDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: rootDirectory)
        }

        try writeText("gitdir: ../metadata\n", to: repositoryDirectory.appendingPathComponent(".git"))
        try writeText("ref: refs/heads/worktree\n", to: actualGitDirectory.appendingPathComponent("HEAD"))

        let branchName = GitBranchResolver().branchName(forWorkingDirectory: repositoryDirectory.path)

        XCTAssertEqual(branchName, "worktree")
    }

    /// Verifies detached HEAD state hides the branch chip.
    func testBranchNameReturnsNilForDetachedHead() throws {
        let context = try makeRepositoryContext()
        try writeText("4f2ef7d6b9ac55f90f4cb1bc59b8c1c5d0adbeef\n", to: context.gitDirectory.appendingPathComponent("HEAD"))

        let branchName = GitBranchResolver().branchName(forWorkingDirectory: context.repositoryDirectory.path)

        XCTAssertNil(branchName)
    }

    /// Verifies directories outside Git repositories do not produce a branch.
    func testBranchNameReturnsNilOutsideGitRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }

        let branchName = GitBranchResolver().branchName(forWorkingDirectory: directory.path)

        XCTAssertNil(branchName)
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
