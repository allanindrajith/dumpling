import Foundation
import AppKit

@MainActor
final class DumplingStore: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var agents: [AgentOverview] = []
    @Published var expandedSessionId: String?
    @Published var isCollapsed: Bool = false
    @Published var isMuted: Bool = false
    @Published var isConnected: Bool = false
    @Published var daemonStarting: Bool = false
    @Published var daemonError: String?

    private let baseURL = URL(string: "http://127.0.0.1:47821")!
    private var pollTimer: Timer?
    private var lastAlertIds: Set<String> = []
    private var spawnedDaemonProcess: Process?
    private var attemptedAutoStart = false

    func start() {
        fetchSessions()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchSessions()
            }
        }
    }

    func fetchSessions() {
        let url = baseURL.appendingPathComponent("sessions")
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil || data == nil {
                    self.isConnected = false
                    self.sessions = []
                    self.agents = []
                    if !self.attemptedAutoStart {
                        self.attemptedAutoStart = true
                        self.startDaemon()
                    }
                    return
                }
                self.isConnected = true
                self.daemonStarting = false
                self.daemonError = nil
                if let data, let decoded = try? JSONDecoder().decode(SessionsPayload.self, from: data) {
                    self.handleUpdatedSessions(decoded.sessions, agents: decoded.agents ?? [])
                }
            }
        }.resume()
    }

    private func handleUpdatedSessions(_ next: [AgentSession], agents: [AgentOverview]) {
        for s in next where s.pendingRequest != nil {
            let reqId = s.pendingRequest?.requestId ?? s.id
            if !lastAlertIds.contains(reqId) {
                lastAlertIds.insert(reqId)
                if !isMuted {
                    NSSound(named: "Tink")?.play()
                }
            }
        }
        self.sessions = next
        self.agents = agents
    }

    func startDaemon() {
        guard !daemonStarting else { return }
        guard let scriptPath = findDaemonScript() else {
            daemonError = "Could not locate daemon/server.mjs"
            return
        }
        guard let nodePath = findNodeBinary() else {
            daemonError = "Node.js not found in PATH"
            return
        }

        daemonStarting = true
        daemonError = nil

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nodePath)
        proc.arguments = [scriptPath]
        let logURL = URL(fileURLWithPath: "/tmp/dumpling-daemon.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            proc.standardOutput = handle
            proc.standardError = handle
        }
        do {
            try proc.run()
            spawnedDaemonProcess = proc
        } catch {
            daemonStarting = false
            daemonError = error.localizedDescription
        }
    }

    func quitApp() {
        pollTimer?.invalidate()
        if let proc = spawnedDaemonProcess, proc.isRunning {
            proc.terminate()
        }
        NSApp.terminate(nil)
    }

    private func findDaemonScript() -> String? {
        let fm = FileManager.default
        var candidates: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["DUMPLING_DAEMON_PATH"] {
            candidates.append(envPath)
        }
        if let execPath = Bundle.main.executablePath {
            var url = URL(fileURLWithPath: execPath).deletingLastPathComponent()
            for _ in 0..<6 {
                candidates.append(url.appendingPathComponent("daemon/server.mjs").path)
                url = url.deletingLastPathComponent()
            }
        }
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("daemon/server.mjs").path)
        return candidates.first { fm.fileExists(atPath: $0) }
    }

    private func findNodeBinary() -> String? {
        let fm = FileManager.default
        let paths = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ]
        if let found = paths.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return found
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["node"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    func respond(sessionId: String, payload: [String: String]) {
        post(path: "sessions/\(sessionId)/respond", body: payload)
    }

    func focus(sessionId: String) {
        post(path: "sessions/\(sessionId)/focus", body: [:])
    }

    func dismiss(sessionId: String) {
        post(path: "sessions/\(sessionId)/dismiss", body: [:])
    }

    private func post(path: String, body: [String: String]) {
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "\(baseURL.absoluteString)/\(encodedPath)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            Task { @MainActor in
                self?.fetchSessions()
            }
        }.resume()
    }
}
