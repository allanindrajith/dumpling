import SwiftUI

struct DumplingShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var p = Path()

        // Start at top-center pinched crest
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.10))
        // Right top pleat & shoulder
        p.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.25),
            control1: CGPoint(x: w * 0.60, y: h * 0.10),
            control2: CGPoint(x: w * 0.65, y: h * 0.20)
        )
        // Right plump cheek down to base
        p.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.84),
            control1: CGPoint(x: w * 0.94, y: h * 0.38),
            control2: CGPoint(x: w * 1.00, y: h * 0.70)
        )
        // Gentle rounded bottom
        p.addQuadCurve(
            to: CGPoint(x: w * 0.12, y: h * 0.84),
            control: CGPoint(x: w * 0.50, y: h * 0.96)
        )
        // Left plump cheek up to shoulder
        p.addCurve(
            to: CGPoint(x: w * 0.28, y: h * 0.25),
            control1: CGPoint(x: w * 0.00, y: h * 0.70),
            control2: CGPoint(x: w * 0.06, y: h * 0.38)
        )
        // Left top pleat back to crest
        p.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.10),
            control1: CGPoint(x: w * 0.35, y: h * 0.20),
            control2: CGPoint(x: w * 0.40, y: h * 0.10)
        )
        p.closeSubpath()
        return p
    }
}

struct BuddyAvatarView: View {
    let color: Color
    let status: String
    let isAlert: Bool

    private var statusDotColor: Color {
        if isAlert { return Color(red: 0.85, green: 0.94, blue: 0.30) }
        switch status {
        case "running": return .green
        case "error": return .red
        default: return Color.white.opacity(0.35)
        }
    }

    private var isSleeping: Bool {
        status == "idle" || status == "done"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                DumplingShape()
                    .fill(isSleeping ? color.opacity(0.45) : color)
                    .frame(width: 30, height: 30)

                // Subtle top pleats
                Path { p in
                    p.move(to: CGPoint(x: 15, y: 5))
                    p.addLine(to: CGPoint(x: 15, y: 9.5))
                    p.move(to: CGPoint(x: 11.5, y: 6.5))
                    p.addLine(to: CGPoint(x: 12.8, y: 10))
                    p.move(to: CGPoint(x: 18.5, y: 6.5))
                    p.addLine(to: CGPoint(x: 17.2, y: 10))
                }
                .stroke(Color.black.opacity(0.28), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 30, height: 30)

                VStack(spacing: 3.5) {
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(Color.black.opacity(0.82))
                            .frame(width: 3.5, height: isSleeping ? 2 : 5)
                        Capsule()
                            .fill(Color.black.opacity(0.82))
                            .frame(width: 3.5, height: isSleeping ? 2 : 5)
                    }
                    Capsule()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: isAlert ? 5 : 9, height: isAlert ? 3 : 2)
                }
                .offset(y: 3.5)
            }

            Circle()
                .fill(statusDotColor)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color(red: 0.08, green: 0.085, blue: 0.10), lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
    }
}

struct DumplingPanelView: View {
    @ObservedObject var store: DumplingStore
    var onHide: (() -> Void)? = nil
    @State private var selectedOptions: [String: String] = [:]
    @State private var manuallyCollapsedIds: Set<String> = []
    @State private var showHistory: Bool = false

    private let accentYellow = Color(red: 0.85, green: 0.94, blue: 0.30)

    var body: some View {
        Group {
            if store.isCollapsed {
                minimizedPill
            } else {
                expandedPanel
            }
        }
        .background(Color(red: 0.08, green: 0.085, blue: 0.10).opacity(0.985))
        .clipShape(RoundedRectangle(cornerRadius: store.isCollapsed ? 20 : 14))
        .overlay(
            RoundedRectangle(cornerRadius: store.isCollapsed ? 20 : 14)
                .stroke(hasAnyAlert ? accentYellow.opacity(0.75) : Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 20, x: 0, y: 10)
    }

    private var hasAnyAlert: Bool {
        store.sessions.contains { $0.pendingRequest != nil }
    }

    private var workingCount: Int {
        store.sessions.filter { $0.effectiveIsWorking }.count
    }

    private var pillDotColor: Color {
        if !store.isConnected { return .red }
        if hasAnyAlert { return accentYellow }
        if workingCount > 0 { return .green }
        return Color.white.opacity(0.4)
    }

    private var pillTitle: String {
        if !store.isConnected { return "Offline" }
        if hasAnyAlert { return "\(workingCount) · Action!" }
        if workingCount > 0 { return "\(workingCount) working" }
        return "Not working"
    }

    private var minimizedPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pillDotColor)
                .frame(width: 7, height: 7)

            HStack(spacing: -3) {
                ForEach(store.sessions.prefix(4)) { s in
                    Circle()
                        .fill(s.effectiveIsWorking ? s.buddyColor : s.buddyColor.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                }
            }

            Text(pillTitle)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(hasAnyAlert ? accentYellow : .white)

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.isCollapsed = false
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Expand")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 210)
    }

    private var visibleAgents: [AgentOverview] {
        store.agents.filter { agent in
            agent.detail != "Not running" || store.sessions.contains { $0.source == agent.id }
        }
    }

    private var primarySessions: [AgentSession] {
        Array(store.sessions.prefix(3))
    }

    private var historySessions: [AgentSession] {
        Array(store.sessions.dropFirst(3))
    }

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerBar

            if !store.isConnected {
                disconnectedBanner
            } else {
                if !visibleAgents.isEmpty {
                    agentsOverviewStrip
                }

                if store.sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(primarySessions) { session in
                                sessionCard(session)
                            }

                            if !historySessions.isEmpty {
                                historySection
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
            }
        }
        .padding(10)
        .frame(width: 300)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(pillDotColor)
                .frame(width: 7, height: 7)

            Text("Dumpling")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Text("\(workingCount)/\(store.sessions.count)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.white.opacity(0.55))

            Spacer()

            Button(action: { store.isMuted.toggle() }) {
                Image(systemName: store.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help(store.isMuted ? "Unmute alerts" : "Mute alerts")

            Button(action: { store.isCollapsed.toggle() }) {
                Image(systemName: store.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("Minimize")

            Button(action: { onHide?() }) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("Hide to Menu Bar")

            Button(action: { store.quitApp() }) {
                Text("Quit")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.red.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Quit Dumpling")
        }
    }

    private var disconnectedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.daemonStarting ? "Starting daemon..." : "Daemon offline")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.orange)

            if let err = store.daemonError {
                Text(err)
                    .font(.system(size: 10.5))
                    .foregroundColor(.red.opacity(0.9))
            } else {
                Text("Run: node daemon/server.mjs")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }

            if !store.daemonStarting {
                Button("Start Daemon") {
                    store.startDaemon()
                }
                .buttonStyle(DumplingActionButtonStyle(bg: Color.white.opacity(0.14), fg: .white))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var agentsOverviewStrip: some View {
        HStack(spacing: 6) {
            ForEach(visibleAgents) { agent in
                HStack(spacing: 4) {
                    Circle()
                        .fill(agentDotColor(agent.status))
                        .frame(width: 6, height: 6)
                    Text(agent.name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(agent.isWorking ? .white : .white.opacity(0.55))
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(agent.isWorking ? 0.09 : 0.035))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .help("\(agent.name): \(agent.detail)")
            }
            Spacer(minLength: 0)
        }
    }

    private func agentDotColor(_ status: String) -> Color {
        switch status {
        case "working": return .green
        case "needs_input": return accentYellow
        case "error": return .red
        default: return .red.opacity(0.65)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red.opacity(0.75))
                .frame(width: 7, height: 7)
            Text("All AI agents not working (no active sessions)")
                .font(.system(size: 11.5))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showHistory.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: showHistory ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                    Text("History (\(historySessions.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            if showHistory {
                VStack(spacing: 5) {
                    ForEach(historySessions) { session in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(session.effectiveIsWorking ? Color.green : session.buddyColor.opacity(0.65))
                                .frame(width: 7, height: 7)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(session.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.88))
                                    .lineLimit(1)
                                Text(session.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.45))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            Button(action: { store.focus(sessionId: session.id) }) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            .buttonStyle(.plain)
                            .help("Open session file/window")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.focus(sessionId: session.id)
                        }
                    }
                }
            }
        }
    }

    private func isDetailsVisible(for session: AgentSession) -> Bool {
        if session.pendingRequest != nil { return false }
        return store.expandedSessionId == session.id
    }

    private func toggleDetails(for session: AgentSession) {
        store.expandedSessionId = store.expandedSessionId == session.id ? nil : session.id
    }

    private func sessionCard(_ session: AgentSession) -> some View {
        let hasAlert = session.pendingRequest != nil
        let showDetails = isDetailsVisible(for: session)
        let isWorking = session.effectiveIsWorking

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                BuddyAvatarView(color: session.buddyColor, status: session.status, isAlert: hasAlert)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(session.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        statusBadge(session)
                    }

                    HStack(spacing: 6) {
                        if let model = session.model, !model.isEmpty {
                            Text(model)
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.48))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        if let ago = relativeTime(session.updatedAt) {
                            Text("· \(ago)")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.38))
                        }

                        Spacer(minLength: 0)
                    }

                    if hasAlert || session.status == "error" {
                        Text(session.subtitle)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(
                                session.status == "error"
                                    ? Color(red: 1.0, green: 0.45, blue: 0.45)
                                    : accentYellow
                            )
                            .lineLimit(2)
                    }
                }

                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                toggleDetails(for: session)
                            }
                        }) {
                            Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                        .help("Show conversation details")

                        Button(action: { store.focus(sessionId: session.id) }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Open session file/window")
                    }

                    Button(action: { store.dismiss(sessionId: session.id) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    toggleDetails(for: session)
                }
            }

            if let req = session.pendingRequest {
                if req.type == "permission" {
                    permissionBlock(session: session, req: req)
                } else if req.type == "question" {
                    questionBlock(session: session, req: req)
                }
            } else if showDetails {
                expandedDetails(session)
            }
        }
        .padding(10)
        .background(Color.white.opacity(hasAlert ? 0.07 : isWorking ? 0.05 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    hasAlert
                        ? accentYellow.opacity(0.85)
                        : session.status == "error"
                        ? Color.red.opacity(0.45)
                        : isWorking
                        ? Color.green.opacity(0.28)
                        : Color.white.opacity(0.06),
                    lineWidth: hasAlert ? 1.2 : 1
                )
        )
    }

    private func statusBadge(_ session: AgentSession) -> some View {
        let label = session.effectiveStatusLabel
        let bg: Color
        let fg: Color

        if session.pendingRequest != nil {
            bg = accentYellow.opacity(0.22)
            fg = accentYellow
        } else if session.status == "error" {
            bg = Color.red.opacity(0.22)
            fg = Color(red: 1.0, green: 0.5, blue: 0.5)
        } else if session.effectiveIsWorking {
            bg = Color.green.opacity(0.2)
            fg = Color(red: 0.45, green: 0.95, blue: 0.58)
        } else {
            bg = Color.white.opacity(0.08)
            fg = Color.white.opacity(0.55)
        }

        return Text(label)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func progressBar(_ progress: DumplingProgress, isWorking: Bool) -> some View {
        let ratio = progress.total > 0 ? CGFloat(progress.completed) / CGFloat(progress.total) : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(progress.completed)/\(progress.total) \(progress.label)")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3.5)
                    Capsule()
                        .fill(isWorking ? accentYellow : Color.white.opacity(0.35))
                        .frame(width: max(6, geo.size.width * ratio), height: 3.5)
                }
            }
            .frame(height: 4)
        }
    }

    private func relativeTime(_ updatedAtMs: Double?) -> String? {
        guard let updatedAtMs else { return nil }
        let secs = max(0, Int((Date().timeIntervalSince1970 * 1000 - updatedAtMs) / 1000))
        if secs < 5 { return "just now" }
        if secs < 60 { return "\(secs)s ago" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }

    private func expandedDetails(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 6) {
                Text(session.source.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                if let cwd = session.cwd, !cwd.isEmpty {
                    Text(URL(fileURLWithPath: cwd).lastPathComponent)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }

                if let model = session.model, !model.isEmpty {
                    Text(model)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer()

                if let ago = relativeTime(session.updatedAt) {
                    Text(ago)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            if let err = session.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.52, blue: 0.52))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !session.steps.isEmpty {
                ForEach(session.steps) { step in
                    HStack(spacing: 6) {
                        Image(
                            systemName: step.status == "done"
                                ? "checkmark.circle.fill"
                                : step.status == "active"
                                ? "circle.dotted"
                                : step.status == "error"
                                ? "exclamationmark.circle.fill"
                                : "circle"
                        )
                        .font(.system(size: 10.5))
                        .foregroundColor(
                            step.status == "done"
                                ? .green
                                : step.status == "active"
                                ? accentYellow
                                : step.status == "error"
                                ? .red
                                : .white.opacity(0.35)
                        )
                        Text(step.text)
                            .font(.system(size: 11))
                            .foregroundColor(step.status == "pending" ? .white.opacity(0.45) : .white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
            }

            if let cmd = session.terminalCommand, !cmd.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("$ \(cmd)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    if let tail = session.terminalTail {
                        ForEach(tail.suffix(2), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func permissionBlock(session: AgentSession, req: PendingRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(req.tool ?? "Tool permission requested")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(2)
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Button("Allow") {
                    store.respond(sessionId: session.id, payload: ["decision": "allow"])
                }
                .buttonStyle(DumplingActionButtonStyle(bg: Color(red: 0.16, green: 0.65, blue: 0.36), fg: .white))

                Button("Deny") {
                    store.respond(sessionId: session.id, payload: ["decision": "deny"])
                }
                .buttonStyle(DumplingActionButtonStyle(bg: Color.white.opacity(0.12), fg: .white.opacity(0.9)))

                Button("In VS Code") {
                    store.respond(sessionId: session.id, payload: ["decision": "open_ide"])
                }
                .buttonStyle(DumplingActionButtonStyle(bg: Color.white.opacity(0.12), fg: .white.opacity(0.9)))
            }
        }
    }

    private func questionBlock(session: AgentSession, req: PendingRequest) -> some View {
        let options = req.options ?? []
        let current = selectedOptions[session.id] ?? options.first ?? ""

        return VStack(alignment: .leading, spacing: 7) {
            if let tag = req.tag, !tag.isEmpty {
                Text(tag)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentYellow)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let prompt = req.prompt {
                Text(prompt)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }

            ForEach(options, id: \.self) { opt in
                HStack(spacing: 7) {
                    Image(systemName: current == opt ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 12))
                        .foregroundColor(current == opt ? accentYellow : .white.opacity(0.45))
                    Text(opt)
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.88))
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(current == opt ? 0.10 : 0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedOptions[session.id] = opt
                }
            }

            HStack(spacing: 6) {
                Button("Send") {
                    store.respond(sessionId: session.id, payload: ["decision": "answer", "answer": current])
                }
                .buttonStyle(DumplingActionButtonStyle(bg: accentYellow, fg: .black))

                Button("Type in VS Code") {
                    store.respond(sessionId: session.id, payload: ["decision": "open_ide"])
                }
                .buttonStyle(DumplingActionButtonStyle(bg: Color.white.opacity(0.12), fg: .white.opacity(0.9)))
            }
        }
    }
}

struct DumplingActionButtonStyle: ButtonStyle {
    let bg: Color
    let fg: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
