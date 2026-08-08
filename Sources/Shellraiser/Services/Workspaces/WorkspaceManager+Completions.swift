import AppKit
import Foundation

/// Activity tracking, completion queue state, and notification flows for the shared manager.
extension WorkspaceManager {
    /// Derives the current activity status for a surface from live completion-tracking state.
    ///
    /// Always computed from `awaitingInputSurfaceIds` / `busySurfaceIds` and the surface's own
    /// `hasPendingCompletion` flag — never a stored value, so it cannot drift from the state that
    /// already drives notifications, the dock badge, and the FIFO completion queue.
    func activityStatus(for surface: SurfaceModel) -> SurfaceActivityStatus {
        if awaitingInputSurfaceIds.contains(surface.id) {
            return .needsInput
        }
        if surface.hasPendingCompletion {
            return .ready
        }
        if busySurfaceIds.contains(surface.id) {
            return .running
        }
        return .idle
    }

    /// Returns whether any live surface in a workspace is currently marked busy.
    func isWorkspaceWorking(workspaceId: UUID) -> Bool {
        guard let workspace = workspace(id: workspaceId) else { return false }

        return workspace.rootPane.allSurfaceIds().contains { busySurfaceIds.contains($0) }
    }

    /// Returns whether any live surface in a workspace is blocked waiting for user input.
    func isWorkspaceAwaitingInput(workspaceId: UUID) -> Bool {
        guard let workspace = workspace(id: workspaceId) else { return false }

        return workspace.rootPane.allSurfaceIds().contains { awaitingInputSurfaceIds.contains($0) }
    }

    /// Returns the number of live surfaces in a workspace currently waiting for user input.
    func awaitingInputCount(workspaceId: UUID) -> Int {
        guard let workspace = workspace(id: workspaceId) else { return 0 }

        return workspace.rootPane.allSurfaceIds().filter { awaitingInputSurfaceIds.contains($0) }.count
    }

    /// Returns whether any surface across the app is currently waiting for user input.
    var hasAwaitingInput: Bool {
        !awaitingInputSurfaceIds.isEmpty
    }

    /// Focuses the first surface currently awaiting user input.
    func jumpToNextSessionAwaitingInput() {
        for workspace in workspaces {
            for surfaceId in workspace.rootPane.allSurfaceIds() {
                if awaitingInputSurfaceIds.contains(surfaceId) {
                    CompletionDebugLogger.log(
                        "focus awaiting-input surface=\(surfaceId.uuidString)"
                    )
                    focusCompletionSurface(surfaceId)
                    return
                }
            }
        }
    }

    /// Enqueues a newly completed agent turn for notifications and FIFO navigation.
    func enqueueCompletion(
        workspaceId: UUID,
        surfaceId: UUID,
        agentType: AgentType,
        timestamp: Date,
        payload: String = ""
    ) {
        let sequence = nextPendingCompletionSequence
        let didEnqueue = surfaceManager.markPendingCompletion(
            workspaceId: workspaceId,
            surfaceId: surfaceId,
            agentType: agentType,
            sequence: sequence,
            timestamp: timestamp,
            workspaces: &workspaces,
            persistence: persistence
        )

        if didEnqueue {
            nextPendingCompletionSequence += 1
            CompletionDebugLogger.log(
                "enqueue workspace=\(workspaceId.uuidString) surface=\(surfaceId.uuidString) sequence=\(sequence)"
            )

            if let target = pendingCompletionTarget(surfaceId: surfaceId),
               let workspace = workspace(id: workspaceId),
               shouldScheduleCompletionNotification(for: surfaceId) {
                completionNotifications.scheduleNotification(
                    target: target,
                    workspaceName: workspace.name
                )
            }
            updateDockBadge()
        } else if !payload.isEmpty {
            surfaceManager.setAgentType(
                workspaceId: workspaceId,
                surfaceId: surfaceId,
                agentType: agentType,
                workspaces: &workspaces,
                persistence: persistence
            )
        }
    }

    /// Focuses the next queued completion target in global FIFO order.
    func jumpToNextCompletedSession() {
        guard let target = pendingCompletionTargets().first else { return }
        focusCompletionSurface(target.surface.id)
    }

    /// Returns whether any queued completions currently exist across the app.
    var hasPendingCompletions: Bool {
        !pendingCompletionTargets().isEmpty
    }

    /// Returns pending completion count for a specific workspace.
    func pendingCompletionCount(workspaceId: UUID) -> Int {
        workspace(id: workspaceId)?.rootPane.pendingCompletionCount() ?? 0
    }

    /// Returns queue position metadata for a pane when it contains pending completions.
    func pendingCompletionQueuePosition(
        workspaceId: UUID,
        paneId: UUID
    ) -> (position: Int, total: Int)? {
        let targets = pendingCompletionTargets()
        guard !targets.isEmpty else { return nil }

        guard let index = targets.firstIndex(where: { target in
            target.workspaceId == workspaceId && target.paneId == paneId
        }) else {
            return nil
        }

        return (position: index + 1, total: targets.count)
    }

    /// Returns queue highlight state for a pane within a workspace.
    func completionHighlightState(workspaceId: UUID, paneId: UUID) -> CompletionPaneHighlightState {
        guard let workspace = workspace(id: workspaceId) else { return .none }
        if workspace.rootPane.containsPendingCompletion(in: paneId) {
            if let target = pendingCompletionTargets().first,
               target.workspaceId == workspaceId,
               target.paneId == paneId {
                return .current
            }

            return .queued
        }

        if let state = recentHighlightState(in: workspace, paneId: paneId) {
            return state
        }

        return .none
    }

    /// Consumes a managed wrapper activity event if the target surface still exists.
    func handleAgentActivityEvent(_ event: AgentActivityEvent) {
        guard let target = surfaceTarget(for: event.surfaceId) else {
            clearBusySurface(event.surfaceId)
            return
        }

        switch event.phase {
        case .started:
            surfaceManager.clearPendingCompletion(
                workspaceId: target.workspaceId,
                surfaceId: event.surfaceId,
                workspaces: &workspaces,
                persistence: persistence
            )
            completionNotifications.removeNotifications(for: event.surfaceId)
            clearSurfaceAwaitingInput(event.surfaceId)
            updateDockBadge()
            markSurfaceBusy(event.surfaceId)
            refreshSessionSummary(workspaceId: target.workspaceId, surfaceId: event.surfaceId)
        case .completed:
            clearBusySurface(event.surfaceId)
            clearSurfaceAwaitingInput(event.surfaceId)
            completionNotifications.removeNotifications(for: event.surfaceId)
            enqueueCompletion(
                workspaceId: target.workspaceId,
                surfaceId: event.surfaceId,
                agentType: event.agentType,
                timestamp: event.timestamp,
                payload: event.payload
            )
            refreshSessionSummary(workspaceId: target.workspaceId, surfaceId: event.surfaceId)
        case .waitingForInput:
            clearBusySurface(event.surfaceId)
            let wasAlreadyAwaiting = awaitingInputSurfaceIds.contains(event.surfaceId)
            markSurfaceAwaitingInput(event.surfaceId)
            refreshSessionSummary(workspaceId: target.workspaceId, surfaceId: event.surfaceId)
            guard !wasAlreadyAwaiting else {
                CompletionDebugLogger.log(
                    "suppress duplicate waiting-for-input surface=\(event.surfaceId.uuidString)"
                )
                return
            }
            completionNotifications.removeNotifications(for: event.surfaceId)
            if let surface = workspace(id: target.workspaceId)?.rootPane.surface(id: event.surfaceId),
               let workspace = workspace(id: target.workspaceId),
               shouldScheduleCompletionNotification(for: event.surfaceId) {
                let fakeTarget = PendingCompletionTarget(
                    workspaceId: target.workspaceId,
                    paneId: target.paneId,
                    surface: surface,
                    sequence: nextPendingCompletionSequence
                )
                completionNotifications.scheduleNotification(
                    target: fakeTarget,
                    workspaceName: workspace.name,
                    kind: .waitingForInput
                )
                CompletionDebugLogger.log(
                    "waiting-for-input notification workspace=\(target.workspaceId.uuidString) surface=\(event.surfaceId.uuidString)"
                )
            }
        case .session:
            let identity = parsedSessionIdentity(from: event)
            surfaceManager.setSessionIdentity(
                workspaceId: target.workspaceId,
                surfaceId: event.surfaceId,
                agentType: event.agentType,
                sessionId: identity.sessionId,
                transcriptPath: identity.transcriptPath,
                workspaces: &workspaces,
                persistence: persistence
            )
        case .exited:
            clearBusySurface(event.surfaceId)
            clearSurfaceAwaitingInput(event.surfaceId)
            clearLiveCodexSessionSurface(event.surfaceId)
            completionNotifications.removeNotifications(for: event.surfaceId)
            guard !isTerminating else { return }
            surfaceManager.setResumeEligibility(
                workspaceId: target.workspaceId,
                surfaceId: event.surfaceId,
                shouldResumeSession: false,
                workspaces: &workspaces,
                persistence: persistence
            )
        }
    }

    /// Focuses a queued completion surface from notifications or jump actions.
    func focusCompletionSurface(_ surfaceId: UUID) {
        guard let target = surfaceTarget(for: surfaceId) else { return }
        CompletionDebugLogger.log(
            "focus completion workspace=\(target.workspaceId.uuidString) surface=\(surfaceId.uuidString)"
        )
        window.selectedWorkspaceId = target.workspaceId
        activateSurface(workspaceId: target.workspaceId, paneId: target.paneId, surfaceId: surfaceId)
    }

    /// Returns the current global FIFO of pending completion targets.
    func pendingCompletionTargets() -> [PendingCompletionTarget] {
        workspaces.flatMap { workspace in
            workspace.rootPane.pendingSurfaceSnapshots().compactMap { snapshot in
                guard let sequence = snapshot.surface.pendingCompletionSequence else { return nil }
                return PendingCompletionTarget(
                    workspaceId: workspace.id,
                    paneId: snapshot.paneId,
                    surface: snapshot.surface,
                    sequence: sequence
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence {
                return lhs.sequence < rhs.sequence
            }

            let lhsDate = lhs.surface.lastCompletionAt ?? lhs.surface.lastActivity
            let rhsDate = rhs.surface.lastCompletionAt ?? rhs.surface.lastActivity
            return lhsDate < rhsDate
        }
    }

    /// Returns queue metadata for a specific surface identifier if it is still mounted in a workspace.
    private func pendingCompletionTarget(surfaceId: UUID) -> PendingCompletionTarget? {
        pendingCompletionTargets().first(where: { $0.surface.id == surfaceId })
    }

    /// Returns pane/workspace routing data for any live surface identifier.
    private func surfaceTarget(for surfaceId: UUID) -> (workspaceId: UUID, paneId: UUID)? {
        for workspace in workspaces {
            if let paneId = workspace.rootPane.paneId(containing: surfaceId) {
                return (workspace.id, paneId)
            }
        }

        return nil
    }

    /// Decodes the stored session payload for a managed runtime into persisted resume metadata.
    private func parsedSessionIdentity(from event: AgentActivityEvent) -> (sessionId: String, transcriptPath: String?) {
        switch event.agentType {
        case .claudeCode:
            let components = event.payload
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .map(String.init)
            let sessionId = components.first ?? ""
            let transcriptPath = components.count > 1 ? components[1] : nil
            return (sessionId, transcriptPath)
        case .codex:
            return (event.payload, nil)
        case .copilot:
            return (event.payload, nil)
        }
    }

    /// Updates the dock icon badge to reflect the current pending completion count.
    func updateDockBadge() {
        let count = pendingCompletionTargets().count
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    /// Rebuilds the next FIFO sequence cursor from persisted surface metadata.
    func synchronizePendingCompletionCursor() {
        let highestSequence = workspaces
            .flatMap { $0.rootPane.pendingSurfaceSnapshots() }
            .compactMap(\.surface.pendingCompletionSequence)
            .max() ?? 0
        nextPendingCompletionSequence = highestSequence + 1
    }

    /// Returns whether a completion should surface as a Notification Center banner.
    private func shouldScheduleCompletionNotification(for surfaceId: UUID) -> Bool {
        guard NSApplication.shared.isActive else { return true }

        if isSurfaceCurrentlyFocused(surfaceId) {
            CompletionDebugLogger.log(
                "suppress notification for focused surface=\(surfaceId.uuidString)"
            )
            return false
        }

        return true
    }

    /// Returns whether the supplied surface currently owns focus in the active app window.
    private func isSurfaceCurrentlyFocused(_ surfaceId: UUID) -> Bool {
        NSApplication.shared.isActive && currentResponderSurfaceId() == surfaceId
    }

    /// Records a handled completion so the pane border can fade out instead of disappearing instantly.
    func markRecentlyHandled(surfaceId: UUID) {
        let fadeStart = Date().addingTimeInterval(5)
        let expiration = fadeStart.addingTimeInterval(1.2)
        recentlyHandledSurfaceFadeStarts[surfaceId] = fadeStart
        recentlyHandledSurfaceExpirations[surfaceId] = expiration

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            guard self.recentlyHandledSurfaceFadeStarts[surfaceId] == fadeStart else { return }
            self.objectWillChange.send()
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(6200))
            guard let self else { return }
            guard self.recentlyHandledSurfaceExpirations[surfaceId] == expiration else { return }
            self.recentlyHandledSurfaceFadeStarts.removeValue(forKey: surfaceId)
            self.recentlyHandledSurfaceExpirations.removeValue(forKey: surfaceId)
            self.objectWillChange.send()
        }

        objectWillChange.send()
    }

    /// Returns the transient handled-highlight state for a pane, if any.
    private func recentHighlightState(
        in workspace: WorkspaceModel,
        paneId: UUID
    ) -> CompletionPaneHighlightState? {
        purgeExpiredRecentHighlights()

        guard let surfaceIds = workspace.rootPane.surfaceIds(in: paneId) else {
            return nil
        }

        let now = Date()
        for surfaceId in surfaceIds {
            guard let expiration = recentlyHandledSurfaceExpirations[surfaceId],
                  expiration > now else {
                continue
            }

            let fadeStart = recentlyHandledSurfaceFadeStarts[surfaceId] ?? expiration
            return now < fadeStart ? .recentHold : .recentFade
        }

        return nil
    }

    /// Removes expired transient handled highlights.
    private func purgeExpiredRecentHighlights() {
        let now = Date()
        recentlyHandledSurfaceFadeStarts = recentlyHandledSurfaceFadeStarts.filter { surfaceId, fadeStart in
            guard let expiration = recentlyHandledSurfaceExpirations[surfaceId] else { return false }
            return fadeStart < expiration && expiration > now
        }
        recentlyHandledSurfaceExpirations = recentlyHandledSurfaceExpirations.filter { $0.value > now }
    }

    /// Marks a surface as currently working.
    func markSurfaceBusy(_ surfaceId: UUID) {
        busySurfaceIds.insert(surfaceId)
    }

    /// Clears working state for one surface.
    func clearBusySurface(_ surfaceId: UUID) {
        busySurfaceIds.remove(surfaceId)
    }

    /// Clears working state for a group of surfaces.
    func clearBusySurfaces<S: Sequence>(_ surfaceIds: S) where S.Element == UUID {
        busySurfaceIds.subtract(surfaceIds)
    }

    /// Marks a surface as blocked waiting for user input or approval.
    func markSurfaceAwaitingInput(_ surfaceId: UUID) {
        awaitingInputSurfaceIds.insert(surfaceId)
    }

    /// Clears waiting-for-input state for one surface.
    func clearSurfaceAwaitingInput(_ surfaceId: UUID) {
        awaitingInputSurfaceIds.remove(surfaceId)
    }

    /// Clears waiting-for-input state for a group of surfaces.
    func clearSurfacesAwaitingInput<S: Sequence>(_ surfaceIds: S) where S.Element == UUID {
        awaitingInputSurfaceIds.subtract(surfaceIds)
    }

    /// Records that the runtime discovered a live Codex session for one surface.
    func markLiveCodexSessionSurface(_ surfaceId: UUID) {
        liveCodexSessionSurfaceIds.insert(surfaceId)
    }

    /// Clears one runtime-discovered Codex session gate.
    func clearLiveCodexSessionSurface(_ surfaceId: UUID) {
        liveCodexSessionSurfaceIds.remove(surfaceId)
    }

    /// Clears runtime-discovered Codex session gates for multiple surfaces.
    func clearLiveCodexSessionSurfaces<S: Sequence>(_ surfaceIds: S) where S.Element == UUID {
        liveCodexSessionSurfaceIds.subtract(surfaceIds)
    }
}
