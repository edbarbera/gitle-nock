import AppKit
import Combine
import SwiftUI

/// Which screen of the expanded menu is showing.
enum MenuScreen: Equatable {
    case main
    case save
    case files
    case repos
    case confirmSend
    case result(ActionResult)
}

struct ActionResult: Equatable {
    let succeeded: Bool
    let title: String
    let detail: String?
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var repos: [Repo] = []
    @Published private(set) var activeRepo: Repo?
    @Published private(set) var status: RepoStatus = .empty
    @Published private(set) var isBusy = false
    @Published private(set) var busyLabel = ""
    @Published var screen: MenuScreen = .main
    @Published var saveMessage: String = ""

    /// True while a system window (the folder chooser) is on screen. The notch
    /// panel sits above the menu bar, so it has to step aside for one.
    @Published private(set) var isPresentingSystemPanel = false
    /// The git account saves are attributed to, shown in Settings.
    @Published private(set) var gitIdentity: (name: String, email: String)?

    let gitleInstalled = GitleRunner.isInstalled
    let settings: Settings

    /// Set by the app delegate, which owns the settings window.
    var onOpenSettings: (() -> Void)?

    /// Serial queue for every subprocess this app runs.
    private static let gitQueue = DispatchQueue(label: "gitlenock.git", qos: .userInitiated)

    private let store = RepoStore()
    private var refreshTimer: Timer?
    /// Set when the user explicitly asks, so a denied folder can be retried.
    private var isUserInitiatedRefresh = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: Settings) {
        self.settings = settings
        repos = store.load()
        let savedID = store.loadActiveID()
        activeRepo = repos.first { $0.id == savedID } ?? repos.first
        refresh()

        settings.$refreshInterval
            .sink { [weak self] interval in self?.startRefreshTimer(every: interval) }
            .store(in: &cancellables)
    }

    private func startRefreshTimer(every interval: TimeInterval) {
        refreshTimer?.invalidate()
        // Files change outside the app constantly; a slow poll keeps the notch honest
        // without the complexity of watching every path with FSEvents.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func openSettings() {
        onOpenSettings?()
    }

    // MARK: - Repos

    func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add project"
        panel.message = "Pick the folder your project lives in."

        // Tell the notch to drop below normal windows before the chooser appears,
        // otherwise the panel — which lives above the menu bar — covers it.
        isPresentingSystemPanel = true
        defer { isPresentingSystemPanel = false }

        // An accessory app needs a real activation for the chooser to come forward.
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        guard !repos.contains(where: { $0.path == path }) else {
            select(repos.first { $0.path == path })
            return
        }

        let repo = Repo(path: path)
        repos.append(repo)
        store.save(repos)
        select(repo)
    }

    func remove(_ repo: Repo) {
        repos.removeAll { $0.id == repo.id }
        store.save(repos)
        if activeRepo?.id == repo.id { select(repos.first) }
    }

    func select(_ repo: Repo?) {
        activeRepo = repo
        store.saveActiveID(repo?.id)
        forceRefresh()
    }

    /// A refresh the user asked for, which retries even a previously blocked folder.
    func forceRefresh() {
        isUserInitiatedRefresh = true
        refresh()
    }

    /// Bundle identifiers to try, in order, when opening the project for editing.
    private static let editorBundleIDs = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
    ]

    /// True when an editor is available, so the UI can say what the button will do.
    var editorIsAvailable: Bool { Self.editorAppURL != nil }

    private static var editorAppURL: URL? {
        editorBundleIDs.lazy
            .compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .first
    }

    func openActiveRepoInEditor() {
        guard let path = activeRepo?.path else { return }
        let folder = URL(fileURLWithPath: path)

        guard let editor = Self.editorAppURL else {
            // Without VS Code installed, Finder is better than doing nothing.
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folder], withApplicationAt: editor, configuration: configuration)
    }

    // MARK: - Status

    func refresh() {
        guard let repo = activeRepo else {
            status = .empty
            return
        }
        // Don't stomp on state mid-action, and don't block the UI on git.
        guard !isBusy else { return }

        // Polling a folder macOS has blocked stalls filesystem calls for every
        // process, not just this one. Once denied, only retry when the user acts.
        if status.accessDenied && !isUserInitiatedRefresh { return }
        isUserInitiatedRefresh = false
        // Subprocesses block their thread. Swift's cooperative pool is small and
        // must never be blocked, so shell work gets its own queue.
        Self.gitQueue.async {
            let fresh = GitReader.status(of: repo.path)
            let identity = GitReader.identity(in: repo.path)
            DispatchQueue.main.async {
                guard self.activeRepo?.id == repo.id else { return }
                self.status = fresh
                self.gitIdentity = identity
            }
        }
    }

    // MARK: - Actions

    func save() {
        let message = saveMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        perform(.save(message: message)) { [weak self] in
            self?.saveMessage = ""
        }
    }

    func send() {
        if settings.confirmBeforeSending {
            screen = .confirmSend
        } else {
            perform(.send)
        }
    }

    func confirmSend() { perform(.send) }
    func grab() { perform(.grab) }

    private func perform(_ action: GitleRunner.Action, onSuccess: (() -> Void)? = nil) {
        guard let repo = activeRepo, !isBusy else { return }

        isBusy = true
        busyLabel = action.runningLabel
        screen = .main

        Self.gitQueue.async {
            let result = GitleRunner.run(action, in: repo.path)
            let detail = GitleRunner.firstMeaningfulLine(of: result.succeeded ? result.stdout : result.message)
            // Re-read on this queue too; the main thread must not wait on git.
            let fresh = GitReader.status(of: repo.path)

            DispatchQueue.main.async {
                self.isBusy = false
                self.busyLabel = ""
                if result.succeeded { onSuccess?() }
                self.screen = .result(ActionResult(
                    succeeded: result.succeeded,
                    title: result.succeeded ? action.successLabel : "That didn't work",
                    detail: detail
                ))
                self.status = fresh
            }
        }
    }

    /// Called when the notch collapses, so the next hover starts somewhere sensible.
    func resetTransientScreens() {
        switch screen {
        case .save, .result, .confirmSend:
            screen = .main
        default:
            break
        }
    }
}
