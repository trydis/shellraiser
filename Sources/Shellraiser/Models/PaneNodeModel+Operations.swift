import Foundation

extension PaneNodeModel {
    /// Cardinal direction for pane focus traversal.
    enum PaneFocusDirection {
        case left
        case right
        case up
        case down
    }

    /// Geometric bounds of a pane leaf in normalized split-tree space.
    private struct PaneBounds {
        let paneId: UUID
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double

        var centerX: Double { (minX + maxX) * 0.5 }
        var centerY: Double { (minY + maxY) * 0.5 }
    }

    /// Smallest allowed split fraction.
    static let minimumSplitRatio: Double = 0.1

    /// Largest allowed split fraction.
    static let maximumSplitRatio: Double = 0.9

    /// Appends a surface into a target leaf pane.
    mutating func appendSurface(to paneId: UUID, surface: SurfaceModel) -> Bool {
        switch self {
        case .leaf(var leaf):
            guard leaf.id == paneId else { return false }
            leaf.surfaces.append(surface)
            leaf.activeSurfaceId = surface.id
            self = .leaf(leaf)
            return true
        case .split(var split):
            if split.first.appendSurface(to: paneId, surface: surface) {
                self = .split(split)
                return true
            }

            if split.second.appendSurface(to: paneId, surface: surface) {
                self = .split(split)
                return true
            }

            return false
        }
    }

    /// Removes a surface from a target leaf pane.
    mutating func removeSurface(from paneId: UUID, surfaceId: UUID) -> Bool {
        switch self {
        case .leaf(var leaf):
            guard leaf.id == paneId else { return false }

            let previousCount = leaf.surfaces.count
            leaf.surfaces.removeAll { $0.id == surfaceId }
            guard leaf.surfaces.count != previousCount else {
                return false
            }

            if leaf.activeSurfaceId == surfaceId {
                leaf.activeSurfaceId = leaf.surfaces.first?.id
            }

            self = .leaf(leaf)
            return true
        case .split(var split):
            if split.first.removeSurface(from: paneId, surfaceId: surfaceId) {
                self = .split(split)
                return true
            }

            if split.second.removeSurface(from: paneId, surfaceId: surfaceId) {
                self = .split(split)
                return true
            }

            return false
        }
    }

    /// Sets active surface for a target leaf pane.
    mutating func setActiveSurface(in paneId: UUID, surfaceId: UUID) -> Bool {
        switch self {
        case .leaf(var leaf):
            guard leaf.id == paneId else { return false }
            guard leaf.surfaces.contains(where: { $0.id == surfaceId }) else { return false }
            leaf.activeSurfaceId = surfaceId
            self = .leaf(leaf)
            return true
        case .split(var split):
            if split.first.setActiveSurface(in: paneId, surfaceId: surfaceId) {
                self = .split(split)
                return true
            }

            if split.second.setActiveSurface(in: paneId, surfaceId: surfaceId) {
                self = .split(split)
                return true
            }

            return false
        }
    }

    /// Activates a surface by identifier and returns its containing pane id.
    mutating func activateSurface(surfaceId: UUID) -> UUID? {
        switch self {
        case .leaf(var leaf):
            guard leaf.surfaces.contains(where: { $0.id == surfaceId }) else { return nil }
            leaf.activeSurfaceId = surfaceId
            self = .leaf(leaf)
            return leaf.id
        case .split(var split):
            if let paneId = split.first.activateSurface(surfaceId: surfaceId) {
                self = .split(split)
                return paneId
            }

            if let paneId = split.second.activateSurface(surfaceId: surfaceId) {
                self = .split(split)
                return paneId
            }

            return nil
        }
    }

    /// Splits a target leaf pane into two child leaves and returns new surface id.
    mutating func splitLeaf(paneId: UUID, orientation: SplitOrientation) -> UUID? {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == paneId else { return nil }

            let newSurface = SurfaceModel.makeDefault()
            let secondLeaf = PaneLeafModel(
                id: UUID(),
                surfaces: [newSurface],
                activeSurfaceId: newSurface.id
            )
            let split = PaneSplitModel(
                id: UUID(),
                orientation: orientation,
                ratio: 0.5,
                first: .leaf(leaf),
                second: .leaf(secondLeaf)
            )
            self = .split(split)
            return newSurface.id
        case .split(var split):
            if let createdSurfaceId = split.first.splitLeaf(paneId: paneId, orientation: orientation) {
                self = .split(split)
                return createdSurfaceId
            }

            if let createdSurfaceId = split.second.splitLeaf(paneId: paneId, orientation: orientation) {
                self = .split(split)
                return createdSurfaceId
            }

            return nil
        }
    }

    /// Updates the split ratio for a target split node.
    mutating func updateSplitRatio(paneId: UUID, ratio: Double) -> Bool {
        switch self {
        case .leaf:
            return false
        case .split(var split):
            if split.id == paneId {
                let clamped = min(Self.maximumSplitRatio, max(Self.minimumSplitRatio, ratio))
                split.ratio = clamped
                self = .split(split)
                return true
            }

            if split.first.updateSplitRatio(paneId: paneId, ratio: ratio) {
                self = .split(split)
                return true
            }

            if split.second.updateSplitRatio(paneId: paneId, ratio: ratio) {
                self = .split(split)
                return true
            }

            return false
        }
    }

    /// Mutates a surface by identifier.
    mutating func mutateSurface(surfaceId: UUID, transform: (inout SurfaceModel) -> Void) -> Bool {
        switch self {
        case .leaf(var leaf):
            guard let index = leaf.surfaces.firstIndex(where: { $0.id == surfaceId }) else {
                return false
            }
            transform(&leaf.surfaces[index])
            self = .leaf(leaf)
            return true
        case .split(var split):
            if split.first.mutateSurface(surfaceId: surfaceId, transform: transform) {
                self = .split(split)
                return true
            }

            if split.second.mutateSurface(surfaceId: surfaceId, transform: transform) {
                self = .split(split)
                return true
            }

            return false
        }
    }

    /// Returns first active surface in tree traversal order.
    func firstActiveSurfaceId() -> UUID? {
        switch self {
        case .leaf(let leaf):
            return leaf.activeSurfaceId ?? leaf.surfaces.first?.id
        case .split(let split):
            return split.first.firstActiveSurfaceId() ?? split.second.firstActiveSurfaceId()
        }
    }

    /// Returns first unread idle surface in tree traversal order.
    func firstUnreadSurfaceId() -> UUID? {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.first(where: { $0.hasUnreadIdleNotification })?.id
        case .split(let split):
            return split.first.firstUnreadSurfaceId() ?? split.second.firstUnreadSurfaceId()
        }
    }

    /// Compacts split nodes when child leaves become empty after tab closes.
    @discardableResult
    mutating func compactEmptyLeaves() -> Bool {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.isEmpty
        case .split(var split):
            let firstIsEmpty = split.first.compactEmptyLeaves()
            let secondIsEmpty = split.second.compactEmptyLeaves()

            if firstIsEmpty && secondIsEmpty {
                self = .leaf(.empty())
                return true
            }

            if firstIsEmpty {
                self = split.second
                return false
            }

            if secondIsEmpty {
                self = split.first
                return false
            }

            self = .split(split)
            return false
        }
    }

    /// Returns the pane leaf identifier that owns a given surface.
    func paneId(containing surfaceId: UUID) -> UUID? {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.contains(where: { $0.id == surfaceId }) ? leaf.id : nil
        case .split(let split):
            return split.first.paneId(containing: surfaceId) ?? split.second.paneId(containing: surfaceId)
        }
    }

    /// Returns whether a leaf pane exists for the given identifier.
    func containsPane(_ paneId: UUID) -> Bool {
        paneNode(id: paneId) != nil
    }

    /// Returns a leaf pane node by identifier.
    func paneNode(id paneId: UUID) -> PaneNodeModel? {
        switch self {
        case .leaf(let leaf):
            return leaf.id == paneId ? self : nil
        case .split(let split):
            return split.first.paneNode(id: paneId) ?? split.second.paneNode(id: paneId)
        }
    }

    /// Returns the first leaf identifier in depth-first order.
    func firstLeafId() -> UUID? {
        switch self {
        case .leaf(let leaf):
            return leaf.id
        case .split(let split):
            return split.first.firstLeafId() ?? split.second.firstLeafId()
        }
    }

    /// Returns all surface ids in a pane leaf preserving tab order.
    func surfaceIds(in paneId: UUID) -> [UUID]? {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == paneId else { return nil }
            return leaf.surfaces.map(\.id)
        case .split(let split):
            return split.first.surfaceIds(in: paneId) ?? split.second.surfaceIds(in: paneId)
        }
    }

    /// Returns all surface ids in this pane tree.
    func allSurfaceIds() -> [UUID] {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.map(\.id)
        case .split(let split):
            return split.first.allSurfaceIds() + split.second.allSurfaceIds()
        }
    }

    /// Returns queued completion count for the full pane tree.
    func pendingCompletionCount() -> Int {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces.filter(\.hasPendingCompletion).count
        case .split(let split):
            return split.first.pendingCompletionCount() + split.second.pendingCompletionCount()
        }
    }

    /// Returns whether a pane leaf currently owns any pending completions.
    func containsPendingCompletion(in paneId: UUID) -> Bool {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == paneId else { return false }
            return leaf.surfaces.contains(where: \.hasPendingCompletion)
        case .split(let split):
            return split.first.containsPendingCompletion(in: paneId)
                || split.second.containsPendingCompletion(in: paneId)
        }
    }

    /// Returns pending completion surfaces along with their owning panes.
    func pendingSurfaceSnapshots() -> [(paneId: UUID, surface: SurfaceModel)] {
        switch self {
        case .leaf(let leaf):
            return leaf.surfaces
                .filter(\.hasPendingCompletion)
                .map { (paneId: leaf.id, surface: $0) }
        case .split(let split):
            return split.first.pendingSurfaceSnapshots() + split.second.pendingSurfaceSnapshots()
        }
    }

    /// Returns active surface id for a specific pane.
    func activeSurfaceId(in paneId: UUID) -> UUID? {
        switch self {
        case .leaf(let leaf):
            guard leaf.id == paneId else { return nil }
            return leaf.activeSurfaceId ?? leaf.surfaces.first?.id
        case .split(let split):
            return split.first.activeSurfaceId(in: paneId) ?? split.second.activeSurfaceId(in: paneId)
        }
    }

    /// Finds the nearest pane in the given direction from a source pane.
    func adjacentPaneId(from sourcePaneId: UUID, direction: PaneFocusDirection) -> UUID? {
        var bounds: [PaneBounds] = []
        collectPaneBounds(minX: 0, minY: 0, maxX: 1, maxY: 1, result: &bounds)

        guard let source = bounds.first(where: { $0.paneId == sourcePaneId }) else {
            return nil
        }

        if let strictMatch = bestAdjacentPaneId(
            candidates: bounds,
            source: source,
            direction: direction,
            mode: .strictEdges
        ) {
            return strictMatch
        }

        return bestAdjacentPaneId(
            candidates: bounds,
            source: source,
            direction: direction,
            mode: .relaxedCenters
        )
    }

    /// Directional scoring mode for pane traversal.
    private enum PaneTraversalMode {
        case strictEdges
        case relaxedCenters
    }

    /// Picks the best directional candidate pane for a given traversal mode.
    private func bestAdjacentPaneId(
        candidates: [PaneBounds],
        source: PaneBounds,
        direction: PaneFocusDirection,
        mode: PaneTraversalMode
    ) -> UUID? {
        var bestPaneId: UUID?
        var bestScore: (axisGap: Double, overlapPenalty: Double, orthDistance: Double)?

        for candidate in candidates where candidate.paneId != source.paneId {
            guard let score = scoreForCandidate(candidate, source: source, direction: direction, mode: mode) else {
                continue
            }

            if bestScore == nil || isScore(score, betterThan: bestScore!) {
                bestPaneId = candidate.paneId
                bestScore = score
            }
        }

        return bestPaneId
    }

    /// Recursively computes normalized bounds for every leaf pane.
    private func collectPaneBounds(
        minX: Double,
        minY: Double,
        maxX: Double,
        maxY: Double,
        result: inout [PaneBounds]
    ) {
        switch self {
        case .leaf(let leaf):
            result.append(
                PaneBounds(
                    paneId: leaf.id,
                    minX: minX,
                    minY: minY,
                    maxX: maxX,
                    maxY: maxY
                )
            )
        case .split(let split):
            let ratio = min(Self.maximumSplitRatio, max(Self.minimumSplitRatio, split.ratio))
            switch split.orientation {
            case .horizontal:
                let midX = minX + (maxX - minX) * ratio
                split.first.collectPaneBounds(minX: minX, minY: minY, maxX: midX, maxY: maxY, result: &result)
                split.second.collectPaneBounds(minX: midX, minY: minY, maxX: maxX, maxY: maxY, result: &result)
            case .vertical:
                let midY = minY + (maxY - minY) * ratio
                split.first.collectPaneBounds(minX: minX, minY: minY, maxX: maxX, maxY: midY, result: &result)
                split.second.collectPaneBounds(minX: minX, minY: midY, maxX: maxX, maxY: maxY, result: &result)
            }
        }
    }

    /// Scores candidate pane fitness for directional focus movement.
    private func scoreForCandidate(
        _ candidate: PaneBounds,
        source: PaneBounds,
        direction: PaneFocusDirection,
        mode: PaneTraversalMode
    ) -> (axisGap: Double, overlapPenalty: Double, orthDistance: Double)? {
        let epsilon = 1e-9

        switch direction {
        case .left:
            if mode == .strictEdges {
                guard candidate.maxX <= source.minX + epsilon else { return nil }
            } else {
                guard candidate.centerX < source.centerX - epsilon else { return nil }
            }
            let axisGap = mode == .strictEdges
                ? source.minX - candidate.maxX
                : source.centerX - candidate.centerX
            let overlap = overlapLength(aMin: source.minY, aMax: source.maxY, bMin: candidate.minY, bMax: candidate.maxY)
            let overlapPenalty: Double = overlap > epsilon ? 0 : 1
            let orthDistance = abs(candidate.centerY - source.centerY)
            return (axisGap, overlapPenalty, orthDistance)
        case .right:
            if mode == .strictEdges {
                guard candidate.minX >= source.maxX - epsilon else { return nil }
            } else {
                guard candidate.centerX > source.centerX + epsilon else { return nil }
            }
            let axisGap = mode == .strictEdges
                ? candidate.minX - source.maxX
                : candidate.centerX - source.centerX
            let overlap = overlapLength(aMin: source.minY, aMax: source.maxY, bMin: candidate.minY, bMax: candidate.maxY)
            let overlapPenalty: Double = overlap > epsilon ? 0 : 1
            let orthDistance = abs(candidate.centerY - source.centerY)
            return (axisGap, overlapPenalty, orthDistance)
        case .up:
            if mode == .strictEdges {
                guard candidate.maxY <= source.minY + epsilon else { return nil }
            } else {
                guard candidate.centerY < source.centerY - epsilon else { return nil }
            }
            let axisGap = mode == .strictEdges
                ? source.minY - candidate.maxY
                : source.centerY - candidate.centerY
            let overlap = overlapLength(aMin: source.minX, aMax: source.maxX, bMin: candidate.minX, bMax: candidate.maxX)
            let overlapPenalty: Double = overlap > epsilon ? 0 : 1
            let orthDistance = abs(candidate.centerX - source.centerX)
            return (axisGap, overlapPenalty, orthDistance)
        case .down:
            if mode == .strictEdges {
                guard candidate.minY >= source.maxY - epsilon else { return nil }
            } else {
                guard candidate.centerY > source.centerY + epsilon else { return nil }
            }
            let axisGap = mode == .strictEdges
                ? candidate.minY - source.maxY
                : candidate.centerY - source.centerY
            let overlap = overlapLength(aMin: source.minX, aMax: source.maxX, bMin: candidate.minX, bMax: candidate.maxX)
            let overlapPenalty: Double = overlap > epsilon ? 0 : 1
            let orthDistance = abs(candidate.centerX - source.centerX)
            return (axisGap, overlapPenalty, orthDistance)
        }
    }

    /// Returns overlap length between two 1D intervals.
    private func overlapLength(aMin: Double, aMax: Double, bMin: Double, bMax: Double) -> Double {
        max(0, min(aMax, bMax) - max(aMin, bMin))
    }

    /// Returns whether the first score is preferred over the second.
    private func isScore(
        _ lhs: (axisGap: Double, overlapPenalty: Double, orthDistance: Double),
        betterThan rhs: (axisGap: Double, overlapPenalty: Double, orthDistance: Double)
    ) -> Bool {
        if lhs.axisGap != rhs.axisGap {
            return lhs.axisGap < rhs.axisGap
        }
        if lhs.overlapPenalty != rhs.overlapPenalty {
            return lhs.overlapPenalty < rhs.overlapPenalty
        }
        return lhs.orthDistance < rhs.orthDistance
    }
}
