import Foundation

/// User-visible tab entry scoped to a pane.
struct SurfaceModel: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var agentType: AgentType
    var sessionId: String
    var terminalConfig: TerminalPanelConfig
    var isIdle: Bool
    var hasUnreadIdleNotification: Bool
    var hasPendingCompletion: Bool
    var pendingCompletionSequence: Int?
    var lastCompletionAt: Date?
    var lastActivity: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case agentType
        case sessionId
        case terminalConfig
        case isIdle
        case hasUnreadIdleNotification
        case hasPendingCompletion
        case pendingCompletionSequence
        case lastCompletionAt
        case lastActivity
    }

    /// Creates a fully specified surface model instance.
    init(
        id: UUID,
        title: String,
        agentType: AgentType,
        sessionId: String,
        terminalConfig: TerminalPanelConfig,
        isIdle: Bool,
        hasUnreadIdleNotification: Bool,
        hasPendingCompletion: Bool,
        pendingCompletionSequence: Int?,
        lastCompletionAt: Date?,
        lastActivity: Date
    ) {
        self.id = id
        self.title = title
        self.agentType = agentType
        self.sessionId = sessionId
        self.terminalConfig = terminalConfig
        self.isIdle = isIdle
        self.hasUnreadIdleNotification = hasUnreadIdleNotification
        self.hasPendingCompletion = hasPendingCompletion
        self.pendingCompletionSequence = pendingCompletionSequence
        self.lastCompletionAt = lastCompletionAt
        self.lastActivity = lastActivity
    }

    /// Decodes persisted surfaces while supplying defaults for newly added completion metadata.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        agentType = try container.decodeIfPresent(AgentType.self, forKey: .agentType) ?? .claudeCode
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId) ?? ""
        terminalConfig = try container.decodeIfPresent(TerminalPanelConfig.self, forKey: .terminalConfig) ?? .default()
        isIdle = try container.decodeIfPresent(Bool.self, forKey: .isIdle) ?? false
        hasUnreadIdleNotification = try container.decodeIfPresent(Bool.self, forKey: .hasUnreadIdleNotification) ?? false
        hasPendingCompletion = try container.decodeIfPresent(Bool.self, forKey: .hasPendingCompletion)
            ?? hasUnreadIdleNotification
        pendingCompletionSequence = try container.decodeIfPresent(Int.self, forKey: .pendingCompletionSequence)
        lastCompletionAt = try container.decodeIfPresent(Date.self, forKey: .lastCompletionAt)
        lastActivity = try container.decodeIfPresent(Date.self, forKey: .lastActivity) ?? Date()
    }

    /// Encodes surfaces with explicit queued completion state.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(agentType, forKey: .agentType)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(terminalConfig, forKey: .terminalConfig)
        try container.encode(isIdle, forKey: .isIdle)
        try container.encode(hasUnreadIdleNotification, forKey: .hasUnreadIdleNotification)
        try container.encode(hasPendingCompletion, forKey: .hasPendingCompletion)
        try container.encodeIfPresent(pendingCompletionSequence, forKey: .pendingCompletionSequence)
        try container.encodeIfPresent(lastCompletionAt, forKey: .lastCompletionAt)
        try container.encode(lastActivity, forKey: .lastActivity)
    }

    /// Creates a surface with sensible defaults for new tabs.
    static func makeDefault(agentType: AgentType = .claudeCode) -> SurfaceModel {
        SurfaceModel(
            id: UUID(),
            title: "~",
            agentType: agentType,
            sessionId: "",
            terminalConfig: .default(),
            isIdle: false,
            hasUnreadIdleNotification: false,
            hasPendingCompletion: false,
            pendingCompletionSequence: nil,
            lastCompletionAt: nil,
            lastActivity: Date()
        )
    }
}
