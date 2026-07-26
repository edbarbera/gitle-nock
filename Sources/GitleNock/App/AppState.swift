import AppKit
import Combine
import SwiftUI

/// Which screen of the expanded menu is showing.
enum MenuScreen: Equatable {
    case main
    /// Tick-list of changed files, everything on by default.
    case pickFiles
    /// Secrets or oversized files were spotted in the picked set.
    case risks(RiskReport)
    case save
    case files
    case repos
    case confirmSend
    /// Sending straight to a shared branch like main.
    case confirmProtectedSend(String)
    /// The project has no online home yet.
    case connect
    /// First-time setup for a folder git doesn't track yet.
    case setup
    case undo
    case confirmDiscard
    case conflicts
    case result(ActionResult)
}

struct ActionResult: Equatable {
    let succeeded: Bool
    let title: String
    let detail: String?
    /// Files the action brought in or touched. Populated for a grab, so the
    /// panel can show what arrived rather than only that something did.
    var files: [FileChange] = []
}

/// A short-lived note shown in the collapsed notch, so an action that finishes
/// after the panel has closed still reports back. Modelled on a Live Activity:
/// it never asks for anything, it just says what happened and fades.
struct PanelActivity: Equatable {
    enum Kind: Equatable { case working, success, failure }

    let kind: Kind
    let icon: String
    let text: String

    /// Bumped on every new activity so the pill re-animates even when two
    /// identical notes land back to back.
    var token: Int = 0
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var repos: [Repo] = []
    @Published private(set) var activeRepo: Repo?
    @Published var status: RepoStatus = .empty
    @Published var isBusy = false
    @Published var busyLabel = ""
    @Published var screen: MenuScreen = .main
    @Published var saveMessage: String = ""

    /// Files ticked on the save checklist. Seeded with everything that changed,
    /// so the common case is still one tap.
    @Published var pickedPaths: Set<String> = []

    /// Conflicts from a half-finished grab, plus what the user chose for each.
    @Published var conflicts: [ConflictFile] = []

    /// Fields for the first-run setup flow and the "connect to GitHub" screen.
    @Published var setupName: String = ""
    @Published var setupEmail: String = ""
    @Published var setupWantsGitignore: Bool = true
    @Published var setupWantsFirstSave: Bool = true
    @Published var remoteURL: String = ""

    /// The description on the last save, shown before undoing it.
    @Published var lastSaveMessage: String?

    /// What the collapsed notch is currently reporting, if anything.
    @Published var activity: PanelActivity?

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
    static let gitQueue = DispatchQueue(label: "gitlenock.git", qos: .userInitiated)

    var activityToken = 0
    /// True when an action finished while the menu was shut, so its result
    /// screen is waiting for the user to hover and read it.
    var resultAwaitingReview = false
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
        // Activating when already active still costs a round trip through the
        // window server on some macOS versions, so skip it when there's nothing to do.
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
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
        "com.microsoft.VSCodeInsiders"
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
        open(URL(fileURLWithPath: path))
    }

    /// Opens one file, used when someone wants to sort a conflict out by hand.
    func openInEditor(relativePath: String) {
        guard let root = activeRepo?.path else { return }
        open(URL(fileURLWithPath: (root as NSString).appendingPathComponent(relativePath)))
    }

    private func open(_ target: URL) {
        guard let editor = Self.editorAppURL else {
            // Without VS Code installed, Finder is better than doing nothing.
            NSWorkspace.shared.selectFile(
                target.path,
                inFileViewerRootedAtPath: target.deletingLastPathComponent().path
            )
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([target], withApplicationAt: editor, configuration: configuration)
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
            let read = Self.readRepoState(repo.path)
            DispatchQueue.main.async {
                guard self.activeRepo?.id == repo.id else { return }
                self.status = read.status
                self.gitIdentity = read.identity
                self.lastSaveMessage = read.lastSaveMessage
            }
        }
    }

    /// A concurrent queue for fanning independent reads out from `gitQueue`.
    /// `gitQueue` itself is serial (subprocess work must not pile onto the
    /// cooperative pool), so waiting on sub-tasks submitted back to `gitQueue`
    /// would deadlock — it only ever runs one block at a time.
    private nonisolated static let readFanoutQueue = DispatchQueue(
        label: "gitlenock.git.fanout",
        attributes: .concurrent
    )

    /// `status`, `identity`, and the last save message are all independent reads.
    /// Running them one after another was the biggest single cost in a refresh —
    /// this fires on every hover, every repo switch, and after every action.
    /// `nonisolated` because it always runs on `gitQueue`, off the main actor.
    struct RepoReadResult {
        var status: RepoStatus
        var identity: (name: String, email: String)?
        var lastSaveMessage: String?
    }

    nonisolated static func readRepoState(_ path: String) -> RepoReadResult {
        var status = RepoStatus.empty
        var identity: (name: String, email: String)?

        let group = DispatchGroup()
        group.enter(); readFanoutQueue.async { status = GitReader.status(of: path); group.leave() }
        group.enter(); readFanoutQueue.async { identity = GitReader.identity(in: path); group.leave() }
        group.wait()

        // Only worth asking once we know there's a commit to describe.
        let last = status.hasCommits ? GitReader.lastSaveMessage(in: path) : nil
        return RepoReadResult(status: status, identity: identity, lastSaveMessage: last)
    }

}
