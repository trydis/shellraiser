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
    ///
    /// Cancels any in-flight task for the same surface before spawning a replacement.
    @discardableResult
    func refreshGitBranch(workspaceId: UUID, surfaceId: UUID, workingDirectory: String) -> Task<Void, Never> {
        gitBranchTasks[surfaceId]?.cancel()

        let requestedWorkingDirectory = workingDirectory
        let gitStateResolver = self.gitStateResolver

        let task = Task.detached(priority: .utility) { [weak self] in
            let gitState = gitStateResolver(requestedWorkingDirectory)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                // Re-check after the actor hop: a replacement task may have cancelled
                // this one between the pre-hop check and the write below.
                guard !Task.isCancelled else { return }
                guard let workspace = workspace(id: workspaceId),
                      let surface = surface(in: workspace.rootPane, surfaceId: surfaceId),
                      surface.terminalConfig.workingDirectory == requestedWorkingDirectory else {
                    return
                }

                gitStatesBySurfaceId[surfaceId] = gitState
            }
        }

        gitBranchTasks[surfaceId] = task
        return task
    }

    /// Removes cached Git state for a surface that is no longer present.
    func clearGitBranch(surfaceId: UUID) {
        gitBranchTasks[surfaceId]?.cancel()
        gitBranchTasks.removeValue(forKey: surfaceId)
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
