import Foundation

/// Git metadata resolution and focused-surface caching for workspace rows.
extension WorkspaceManager {
    /// Returns the focused surface's resolved Git state for a workspace when available.
    func focusedGitState(workspaceId: UUID) -> ResolvedGitState? {
        guard let workspace = workspace(id: workspaceId),
              let surfaceId = workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId() else {
            return nil
        }

        return gitStatesBySurfaceId[surfaceId]
    }

    /// Seeds or refreshes Git state for each workspace's focused surface.
    func refreshFocusedWorkspaceGitBranches() {
        for workspace in workspaces {
            guard let surfaceId = workspace.focusedSurfaceId ?? workspace.rootPane.firstActiveSurfaceId(),
                  let surface = surface(in: workspace.rootPane, surfaceId: surfaceId) else {
                continue
            }

            refreshGitBranch(
                workspaceId: workspace.id,
                surfaceId: surfaceId,
                workingDirectory: surface.terminalConfig.workingDirectory
            )
        }
    }

    /// Refreshes the resolved Git state for a surface working directory.
    func refreshGitBranch(workspaceId: UUID, surfaceId: UUID, workingDirectory: String) {
        let requestedWorkingDirectory = workingDirectory

        Task.detached(priority: .utility) {
            let gitState = GitBranchResolver().resolveGitState(forWorkingDirectory: requestedWorkingDirectory)
            await MainActor.run {
                guard let workspace = self.workspace(id: workspaceId),
                      let surface = self.surface(in: workspace.rootPane, surfaceId: surfaceId),
                      surface.terminalConfig.workingDirectory == requestedWorkingDirectory else {
                    return
                }

                self.gitStatesBySurfaceId[surfaceId] = gitState
            }
        }
    }

    /// Removes cached Git state for a surface that is no longer present.
    func clearGitBranch(surfaceId: UUID) {
        gitStatesBySurfaceId.removeValue(forKey: surfaceId)
    }

    /// Returns a surface snapshot by identifier anywhere in a pane tree.
    func surface(in rootPane: PaneNodeModel, surfaceId: UUID) -> SurfaceModel? {
        switch rootPane {
        case .leaf(let leaf):
            return leaf.surfaces.first(where: { $0.id == surfaceId })
        case .split(let split):
            return surface(in: split.first, surfaceId: surfaceId) ?? surface(in: split.second, surfaceId: surfaceId)
        }
    }
}
