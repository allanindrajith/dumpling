import Foundation
import SwiftUI

struct DumplingStep: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let status: String // "done" | "active" | "pending" | "error"
}

struct DumplingProgress: Codable, Equatable {
    let completed: Int
    let total: Int
    let label: String
}

struct PendingRequest: Codable, Equatable {
    let type: String // "permission" | "question"
    let requestId: String
    let tool: String?
    let detail: String?
    let tag: String?
    let prompt: String?
    let options: [String]?
}

struct AgentOverview: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let status: String // "working" | "needs_input" | "error" | "not_working"
    let isWorking: Bool
    let detail: String
    let activeCount: Int
}

struct AgentSession: Codable, Identifiable, Equatable {
    let id: String
    let source: String
    let title: String
    let subtitle: String
    let color: String
    let status: String // "running" | "needs_permission" | "asking_question" | "idle" | "done" | "error"
    let isWorking: Bool?
    let statusLabel: String?
    let errorMessage: String?
    let model: String?
    let activeTool: String?
    let progress: DumplingProgress
    let steps: [DumplingStep]
    let terminalCommand: String?
    let terminalTail: [String]?
    let pendingRequest: PendingRequest?
    let cwd: String?
    let ide: String?
    let updatedAt: Double?

    var effectiveIsWorking: Bool {
        if let isWorking { return isWorking }
        return status == "running" || status == "needs_permission" || status == "asking_question"
    }

    var effectiveStatusLabel: String {
        if let statusLabel { return statusLabel }
        switch status {
        case "running": return "Working"
        case "needs_permission", "asking_question": return "Needs Input"
        case "error": return "Error"
        default: return "Not Working"
        }
    }

    var buddyColor: Color {
        switch color {
        case "blue": return Color(red: 0.34, green: 0.56, blue: 1.0)
        case "pink": return Color(red: 0.94, green: 0.42, blue: 0.68)
        case "orange": return Color(red: 0.96, green: 0.58, blue: 0.28)
        case "purple": return Color(red: 0.62, green: 0.52, blue: 0.98)
        default: return Color(red: 0.36, green: 0.84, blue: 0.55)
        }
    }
}

struct SessionsPayload: Codable {
    let sessions: [AgentSession]
    let agents: [AgentOverview]?
}
