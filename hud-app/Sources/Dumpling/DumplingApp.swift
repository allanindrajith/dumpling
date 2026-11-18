import AppKit
import SwiftUI
import Combine

final class FloatingHudPanel: NSPanel {
    private var pendingDragEvent: NSEvent?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 100),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovable = true
        self.isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            pendingDragEvent = event
            super.sendEvent(event)
        case .leftMouseDragged:
            if let startEvent = pendingDragEvent {
                let dx = event.locationInWindow.x - startEvent.locationInWindow.x
                let dy = event.locationInWindow.y - startEvent.locationInWindow.y
                if hypot(dx, dy) >= 3 {
                    pendingDragEvent = nil
                    performDrag(with: startEvent)
                    return
                }
            }
            super.sendEvent(event)
        case .leftMouseUp:
            pendingDragEvent = nil
            super.sendEvent(event)
        default:
            super.sendEvent(event)
        }
    }
}

@main
struct DumplingApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingHudPanel?
    private var hostingView: NSHostingView<DumplingPanelView>?
    private var statusItem: NSStatusItem?
    private let store = DumplingStore()
    private var cancellables = Set<AnyCancellable>()
    private var lastNotifiedIds = Set<String>()
    private var hasPositioned = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        bindStore()
        store.start()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Dumpling")
            button.imagePosition = .imageLeading
            button.title = " 0"
            button.target = self
            button.action = #selector(togglePanel)
        }
        self.statusItem = item
    }

    private func setupPanel() {
        let hosting = NSHostingView(rootView: DumplingPanelView(store: store, onHide: { [weak self] in
            self?.panel?.orderOut(nil)
        }))
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hostingView = hosting

        let hudPanel = FloatingHudPanel(contentView: hosting)
        self.panel = hudPanel
        resizeAndAnchorPanel()
        hudPanel.orderFrontRegardless()
    }

    private func bindStore() {
        store.$sessions
            .combineLatest(store.$expandedSessionId, store.$isCollapsed, store.$isConnected)
            .combineLatest(store.$agents, store.$daemonStarting)
            .receive(on: RunLoop.main)
            .sink { [weak self] first, _, _ in
                guard let self else { return }
                let (sessions, _, _, _) = first
                self.updateStatusItem(sessions: sessions)
                self.notifyIfNeeded(sessions: sessions)
                // Delay 1 tick so SwiftUI layout updates intrinsicContentSize
                DispatchQueue.main.async {
                    self.resizeAndAnchorPanel()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem(sessions: [AgentSession]) {
        guard let button = statusItem?.button else { return }
        let hasAlert = sessions.contains { $0.pendingRequest != nil }
        let workingCount = sessions.filter { $0.effectiveIsWorking }.count
        let symbolName = hasAlert ? "exclamationmark.bubble.fill" : "square.grid.2x2.fill"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Dumpling")
        button.title = hasAlert ? " \(workingCount)!" : " \(workingCount)"
    }

    private func notifyIfNeeded(sessions: [AgentSession]) {
        for s in sessions where s.pendingRequest != nil {
            let reqId = s.pendingRequest?.requestId ?? s.id
            if !lastNotifiedIds.contains(reqId) {
                lastNotifiedIds.insert(reqId)
                // Auto-show HUD when an agent needs attention
                if store.isCollapsed { store.isCollapsed = false }
                panel?.orderFrontRegardless()
                sendMacNotification(title: "Dumpling · \(s.title)", body: s.subtitle)
            }
        }
    }

    private func sendMacNotification(title: String, body: String) {
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
        let safeBody = body.replacingOccurrences(of: "\"", with: "'")
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", "display notification \"\(safeBody)\" with title \"\(safeTitle)\""]
        try? task.run()
    }

    private func resizeAndAnchorPanel() {
        guard let panel, let hostingView else { return }
        let fitting = hostingView.fittingSize
        let width: CGFloat = store.isCollapsed ? 210 : 350
        let height = max(38, min(fitting.height, 640))

        if !hasPositioned, let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let x = vf.maxX - width - 14
            let y = vf.maxY - height - 10
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            hasPositioned = true
            return
        }

        // Preserve the user's dragged position (keep top-right edge anchored)
        let current = panel.frame
        let newX = current.maxX - width
        let newY = current.maxY - height
        panel.setFrame(NSRect(x: newX, y: newY, width: width, height: height), display: true)
    }

    @objc private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            resizeAndAnchorPanel()
            panel.orderFrontRegardless()
        }
    }
}
