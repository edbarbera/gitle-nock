import AppKit
import Combine
import SwiftUI

/// Owns the panel that sits over the notch and decides when it opens and closes.
@MainActor
final class NotchWindowController {
    /// Wide and shallow, so the menu reads as an extension of the notch rather
    /// than a column hanging off it. The height must clear the tallest screen's
    /// content — anything shorter silently clips the footer off the bottom.
    static let expandedSize = CGSize(width: 780, height: 322)

    /// Above the menu bar, where the notch lives.
    static let floatingLevel = NSWindow.Level(Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)

    private let panel: NotchPanel
    private let state: AppState
    private let viewModel = NotchViewModel()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var collapseWorkItem: DispatchWorkItem?
    private var geometry: NotchGeometry?
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state

        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        // Above the menu bar, and present on every space and over full-screen apps.
        panel.level = Self.floatingLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        panel.contentView = NotchHostingView(
            rootView: NotchRootView()
                .environmentObject(state)
                .environmentObject(viewModel)
                .environmentObject(state.settings)
        )

        // Typing in the save box shouldn't be interrupted by the cursor wandering off.
        state.$screen
            .combineLatest(state.$isBusy)
            .sink { [weak self] screen, busy in
                self?.viewModel.setPin(.busy, busy)
                self?.viewModel.setPin(.typing, screen == .save)
            }
            .store(in: &cancellables)

        // The folder chooser is an ordinary window; this panel normally floats above
        // the menu bar. Drop below while it's up, and stay open behind it.
        state.$isPresentingSystemPanel
            .sink { [weak self] presenting in
                guard let self else { return }
                self.viewModel.setPin(.systemPanel, presenting)
                self.panel.level = presenting ? .normal : Self.floatingLevel
                if presenting { self.expand() }
            }
            .store(in: &cancellables)

        state.settings.$showPillWithoutNotch
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.reposition() }
            }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    func start() {
        reposition()
        panel.orderFrontRegardless()
        installMouseMonitors()
        installDebugToggle()

        // Querying notch geometry the instant the app launches can catch macOS
        // before the window server has settled, reading back a nil/zero notch
        // area on hardware that really has one. A cheap second pass a moment
        // later corrects a pill that's stuck showing on a real notch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.reposition()
        }
    }

    /// Lets the menu be driven without a cursor, so the UI can be inspected and
    /// screenshotted from a script. The notification's object selects a command:
    /// "addrepo", "settings", "editor", or nil to toggle the menu open and shut.
    ///
    /// Off unless GITLENOCK_DEBUG=1. It is a system-wide notification, so leaving
    /// it always-on would let any process on the Mac pop this app's folder chooser.
    private func installDebugToggle() {
        guard ProcessInfo.processInfo.environment["GITLENOCK_DEBUG"] == "1" else { return }
        DistributedNotificationCenter.default().addObserver(
            forName: .init("com.edbarbera.gitlenock.toggle"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self else { return }
                switch note.object as? String {
                case "addrepo": self.state.addRepo(); return
                case "settings": self.state.openSettings(); return
                case "editor": self.state.openActiveRepoInEditor(); return
                default: break
                }
                if self.viewModel.pinReasons.contains(.debug) {
                    self.viewModel.setPin(.debug, false)
                    self.collapse()
                } else {
                    self.expand()
                    // Nothing is hovering it, so hold it open until told otherwise.
                    self.viewModel.setPin(.debug, true)
                }
            }
        }
    }

    // MARK: - Layout

    private func reposition() {
        guard let geo = NotchGeometry.current(
            showFallbackPill: state.settings.showPillWithoutNotch
        ) else { return }
        geometry = geo
        viewModel.collapsedSize = geo.collapsedSize
        viewModel.isRealNotch = geo.isRealNotch
        panel.setFrame(geo.expandedRect(size: Self.expandedSize), display: true)

        // No notch and no pill wanted: get off the screen entirely.
        if geo.isHidden {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Hover

    private func installMouseMonitors() {
        // Global fires while the pointer is over other apps; local fires once it
        // reaches our own panel. Together they cover the whole screen.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.evaluatePointer() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in self?.evaluatePointer() }
            return event
        }
    }

    private func evaluatePointer() {
        guard let geometry, !geometry.isHidden else { return }
        let mouse = NSEvent.mouseLocation

        if viewModel.isExpanded {
            // Stay open anywhere over the panel, not just the pill.
            let stayOpen = panel.frame.insetBy(dx: -8, dy: -8).contains(mouse)
            if stayOpen {
                cancelPendingCollapse()
            } else {
                scheduleCollapse()
            }
        } else if geometry.hoverRect.contains(mouse) {
            expand()
        }
    }

    private func expand() {
        cancelPendingCollapse()
        guard !viewModel.isExpanded else { return }

        // Clicks must land now, so stop passing them through to whatever is beneath.
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        panel.makeKey()
        state.refresh()

        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            viewModel.isExpanded = true
        }
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.collapse() }
        }
        collapseWorkItem = work
        // Grace period so travelling from the pill to the menu doesn't flicker it
        // shut. Short enough that leaving the panel still reads as immediate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func cancelPendingCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    private func collapse() {
        collapseWorkItem = nil
        guard viewModel.isExpanded, !viewModel.isPinned else { return }

        state.resetTransientScreens()
        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
            viewModel.isExpanded = false
        }
        panel.resignKey()

        // Once collapsed the panel is mostly transparent, so let clicks fall through
        // to the menu bar underneath it. Timed to the animation above, not the old
        // grace period — closing shouldn't feel like it lingers after the mouse leaves.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, !self.viewModel.isExpanded else { return }
            self.panel.ignoresMouseEvents = true
        }
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}

/// Presentation state shared between the controller and the SwiftUI tree.
@MainActor
final class NotchViewModel: ObservableObject {
    /// Why the panel is currently refusing to close. Tracked as a set because
    /// several can apply at once — a single flag lets one condition clear
    /// another's hold and collapse the menu out from under the user.
    enum PinReason: Hashable {
        case busy
        case typing
        case systemPanel
        case debug
    }

    @Published var isExpanded = false
    @Published var collapsedSize = NotchGeometry.fallbackSize
    @Published var isRealNotch = false
    @Published private(set) var pinReasons: Set<PinReason> = []

    /// While pinned, the panel refuses to auto-collapse.
    var isPinned: Bool { !pinReasons.isEmpty }

    func setPin(_ reason: PinReason, _ active: Bool) {
        if active { pinReasons.insert(reason) } else { pinReasons.remove(reason) }
    }
}
