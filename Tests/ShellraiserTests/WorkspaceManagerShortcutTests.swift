import AppKit
import XCTest
@testable import Shellraiser

/// Covers keyboard shortcut routing for app-level workspace and pane commands.
@MainActor
final class WorkspaceManagerShortcutTests: WorkspaceTestCase {
    /// Verifies core command shortcuts trigger workspace creation and command-palette toggling.
    func testHandleLocalShortcutTriggersWorkspaceAndPaletteCommands() {
        let manager = makeWorkspaceManager()

        let didCreateWorkspace = manager.handleLocalShortcut(
            makeKeyEvent(characters: "n", modifierFlags: [.command], keyCode: 45)
        )
        let didTogglePalette = manager.handleLocalShortcut(
            makeKeyEvent(characters: "p", modifierFlags: [.command, .shift], keyCode: 35)
        )

        XCTAssertTrue(didCreateWorkspace)
        XCTAssertEqual(manager.workspaces.count, 1)
        XCTAssertEqual(manager.window.selectedWorkspaceId, manager.workspaces[0].id)
        XCTAssertTrue(didTogglePalette)
        XCTAssertTrue(manager.isCommandPalettePresented)
    }

    /// Verifies numeric command shortcuts select workspaces by display index.
    func testHandleLocalShortcutSelectsWorkspaceByDisplayIndex() {
        let manager = makeWorkspaceManager()
        let first = WorkspaceModel.makeDefault(name: "One")
        let second = WorkspaceModel.makeDefault(name: "Two")
        manager.workspaces = [first, second]

        let didSelect = manager.handleLocalShortcut(
            makeKeyEvent(characters: "2", modifierFlags: [.command], keyCode: 19)
        )

        XCTAssertTrue(didSelect)
        XCTAssertEqual(manager.window.selectedWorkspaceId, second.id)
    }

    /// Verifies control-tab cycles pane tabs through the focused-pane command path.
    func testHandleLocalShortcutCyclesPaneTabs() {
        let manager = makeWorkspaceManager()
        let firstSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001501")!,
            title: "First"
        )
        let secondSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001502")!,
            title: "Second"
        )
        let paneId = UUID(uuidString: "00000000-0000-0000-0000-000000001503")!
        let workspaceId = UUID(uuidString: "00000000-0000-0000-0000-000000001504")!
        manager.workspaces = [
            makeWorkspace(
                id: workspaceId,
                name: "Tabs",
                rootPane: makeLeaf(paneId: paneId, surfaces: [firstSurface, secondSurface], activeSurfaceId: firstSurface.id),
                focusedSurfaceId: firstSurface.id
            )
        ]
        manager.window.selectedWorkspaceId = workspaceId

        let didCycleForward = manager.handleLocalShortcut(
            makeKeyEvent(characters: "\t", modifierFlags: [.control], keyCode: 48)
        )

        XCTAssertTrue(didCycleForward)
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, secondSurface.id)

        let didCycleBackward = manager.handleLocalShortcut(
            makeKeyEvent(characters: "\t", modifierFlags: [.control, .shift], keyCode: 48)
        )

        XCTAssertTrue(didCycleBackward)
        XCTAssertEqual(manager.workspaces[0].focusedSurfaceId, firstSurface.id)
    }

    /// Verifies destructive and queue-navigation shortcuts route to delete confirmation and completion focus flows.
    func testHandleLocalShortcutRoutesDeleteAndNextCompletionCommands() {
        var deleteConfirmationRequest: WorkspaceDeletionRequest?
        let manager = makeWorkspaceManager(confirmWorkspaceDeletion: { request in
            deleteConfirmationRequest = request
            return false
        })
        let firstWorkspace = WorkspaceModel.makeDefault(name: "First")
        let pendingSurface = makeSurface(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001511")!,
            title: "Pending",
            isIdle: true,
            hasUnreadIdleNotification: true,
            hasPendingCompletion: true,
            pendingCompletionSequence: 1,
            lastCompletionAt: Date(timeIntervalSince1970: 1_700_006_000)
        )
        let pendingPaneId = UUID(uuidString: "00000000-0000-0000-0000-000000001512")!
        let secondWorkspace = makeWorkspace(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001513")!,
            name: "Second",
            rootPane: makeLeaf(paneId: pendingPaneId, surfaces: [pendingSurface], activeSurfaceId: pendingSurface.id),
            focusedSurfaceId: nil
        )
        manager.workspaces = [firstWorkspace, secondWorkspace]
        manager.window.selectedWorkspaceId = firstWorkspace.id

        let didRequestDelete = manager.handleLocalShortcut(
            makeKeyEvent(characters: "w", modifierFlags: [.command, .shift], keyCode: 13)
        )
        let didJumpToCompletion = manager.handleLocalShortcut(
            makeKeyEvent(characters: "u", modifierFlags: [.command, .shift], keyCode: 32)
        )

        XCTAssertTrue(didRequestDelete)
        XCTAssertEqual(deleteConfirmationRequest?.workspaceId, firstWorkspace.id)
        XCTAssertEqual(manager.workspaces.map(\.id), [firstWorkspace.id, secondWorkspace.id])
        XCTAssertTrue(didJumpToCompletion)
        XCTAssertEqual(manager.window.selectedWorkspaceId, secondWorkspace.id)
        XCTAssertEqual(manager.workspaces[1].focusedSurfaceId, pendingSurface.id)
    }

    /// Creates a synthetic key event for shortcut routing tests.
    private func makeKeyEvent(
        characters: String,
        modifierFlags: NSEvent.ModifierFlags,
        keyCode: UInt16
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
