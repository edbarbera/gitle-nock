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
    @Published private(set) var status: RepoStatus = .empty
    @Published private(set) var isBusy = false
    @Published private(set) var busyLabel = ""
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
    @Published private(set) var lastSaveMessage: String?

    /// What the collapsed notch is currently reporting, if anything.
    @Published private(set) var activity: PanelActivity?

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

    private var activityToken = 0
    /// True when an action finished while the menu was shut, so its result
    /// screen is waiting for the user to hover and read it.
    private var resultAwaitingReview = false
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
            NSWorkspace.shared.selectFile(target.path, inFileViewerRootedAtPath: target.deletingLastPathComponent().path)
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
            let (fresh, identity, last) = Self.readRepoState(repo.path)
            DispatchQueue.main.async {
                guard self.activeRepo?.id == repo.id else { return }
                self.status = fresh
                self.gitIdentity = identity
                self.lastSaveMessage = last
            }
        }
    }

    /// A concurrent queue for fanning independent reads out from `gitQueue`.
    /// `gitQueue` itself is serial (subprocess work must not pile onto the
    /// cooperative pool), so waiting on sub-tasks submitted back to `gitQueue`
    /// would deadlock — it only ever runs one block at a time.
    private nonisolated static let readFanoutQueue = DispatchQueue(label: "gitlenock.git.fanout", attributes: .concurrent)

    /// `status`, `identity`, and the last save message are all independent reads.
    /// Running them one after another was the biggest single cost in a refresh —
    /// this fires on every hover, every repo switch, and after every action.
    /// `nonisolated` because it always runs on `gitQueue`, off the main actor.
    private nonisolated static func readRepoState(_ path: String) -> (RepoStatus, (name: String, email: String)?, String?) {
        var status = RepoStatus.empty
        var identity: (name: String, email: String)?

        let group = DispatchGroup()
        group.enter(); readFanoutQueue.async { status = GitReader.status(of: path); group.leave() }
        group.enter(); readFanoutQueue.async { identity = GitReader.identity(in: path); group.leave() }
        group.wait()

        // Only worth asking once we know there's a commit to describe.
        let last = status.hasCommits ? GitReader.lastSaveMessage(in: path) : nil
        return (status, identity, last)
    }

    // MARK: - Saving

    /// Opens the file checklist with everything ticked — the default is still
    /// "save it all", picking is the opt-in.
    func beginSave() {
        pickedPaths = Set(status.changes.map(\.path))
        screen = .pickFiles
    }

    func togglePick(_ path: String) {
        if pickedPaths.contains(path) {
            pickedPaths.remove(path)
        } else {
            pickedPaths.insert(path)
        }
    }

    func pickAll() { pickedPaths = Set(status.changes.map(\.path)) }
    func pickNone() { pickedPaths = [] }

    var pickedInOrder: [String] {
        status.changes.map(\.path).filter { pickedPaths.contains($0) }
    }

    /// Runs the secret / big-file check on the picked set before asking for a
    /// description, so a warning arrives before the user has typed anything.
    func reviewPicked() {
        guard let repo = activeRepo, !pickedPaths.isEmpty else { return }
        let report = SafetyRails.review(paths: pickedInOrder, root: repo.path)
        screen = report.isEmpty ? .save : .risks(report)
    }

    /// "Leave those out" — unticks every flagged file and carries on.
    func dropFlagged(_ report: RiskReport) {
        pickedPaths.subtract(report.allPaths)
        if pickedPaths.isEmpty {
            screen = .pickFiles
        } else {
            screen = .save
        }
    }

    /// "Save them anyway" — the user has seen the warning and accepted it.
    func acceptRisks() { screen = .save }

    func save() {
        let message = saveMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let repo = activeRepo else { return }
        let paths = pickedInOrder
        guard !paths.isEmpty else { return }

        runWrite(busy: "Saving your work…", failure: "That didn't work",
                 done: "Saved", icon: "tray.and.arrow.down.fill") {
            GitWriter.save(paths: paths, message: message, in: repo.path)
        } onSuccess: { [weak self] in
            self?.saveMessage = ""
            self?.pickedPaths = []
        }
    }

    // MARK: - Sending

    func send() {
        guard let repo = activeRepo else { return }

        guard status.hasCommits else {
            screen = .result(ActionResult(
                succeeded: false,
                title: "Nothing to send yet",
                detail: "Save some work first, then send it online."
            ))
            return
        }

        // No online home: collect a link rather than dead-ending, which is what
        // the CLI's interactive `gitle send` would offer to do here.
        guard status.hasRemote else {
            remoteURL = ""
            screen = .connect
            return
        }

        // The rail gitle can't reach headless: pushing straight to a shared branch.
        if SafetyRails.isProtected(status.branch) {
            screen = .confirmProtectedSend(status.branch)
            return
        }

        if settings.confirmBeforeSending {
            screen = .confirmSend
        } else {
            performSend(in: repo)
        }
    }

    /// Past the protected-branch warning; honour the ordinary confirm too if it's on.
    func confirmProtectedSend() {
        guard let repo = activeRepo else { return }
        if settings.confirmBeforeSending {
            screen = .confirmSend
        } else {
            performSend(in: repo)
        }
    }

    func confirmSend() {
        guard let repo = activeRepo else { return }
        performSend(in: repo)
    }

    private func performSend(in repo: Repo) {
        let branch = status.branch
        let hasUpstream = status.hasUpstream

        runWrite(busy: "Sending it online…", failure: "Couldn't send",
                 done: "Sent online", icon: "arrow.up") {
            GitWriter.send(branch: branch, hasUpstream: hasUpstream, in: repo.path)
        } explain: { result in
            GitWriter.explainPushFailure(result.message)
        }
    }

    /// Connects a GitHub link typed on the connect screen, then sends.
    func connectAndSend() {
        let url = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty, let repo = activeRepo else { return }

        runWrite(busy: "Connecting…", failure: "Couldn't connect that link",
                 done: "Connected", icon: "link") {
            GitWriter.addRemote(url, in: repo.path)
        } onSuccess: { [weak self] in
            self?.remoteURL = ""
            // Straight into the push; connecting on its own accomplishes nothing.
            self?.send()
        }
    }

    // MARK: - Grabbing

    /// The one action still handled by gitle: `grab` has no prompts, so it works
    /// headless and keeps its friendly conflict wording.
    func grab() {
        guard let repo = activeRepo else { return }

        // `work` and `summary` both run on `gitQueue`, in that order, so this
        // hands the pre-grab commit from one to the other without locking.
        let before = Handoff<String>()

        runWrite(busy: "Grabbing the latest…", failure: "Couldn't grab",
                 done: "Up to date", icon: "arrow.down",
                 summary: {
                     guard let old = before.value,
                           let new = GitReader.headSHA(in: repo.path),
                           old != new
                     else { return nil }   // nothing came down; no screen worth showing

                     let files = GitReader.changedFiles(from: old, to: new, in: repo.path)
                     let commits = GitReader.commitCount(from: old, to: new, in: repo.path)
                     return ActionResult(
                         succeeded: true,
                         title: "Got \(commits) update\(commits == 1 ? "" : "s")",
                         detail: nil,
                         files: files
                     )
                 }) {
            before.value = GitReader.headSHA(in: repo.path)
            return GitleRunner.run(.grab, in: repo.path)
        }
    }

    // MARK: - Undoing

    func beginUndo() { screen = .undo }

    func undoLastSave() {
        guard let repo = activeRepo else { return }
        runWrite(busy: "Undoing your last save…", failure: "Couldn't undo",
                 done: "Undone", icon: "arrow.uturn.backward") {
            GitWriter.undoLastSave(in: repo.path)
        }
    }

    func discardAllChanges() {
        guard let repo = activeRepo else { return }
        let hasCommits = status.hasCommits
        runWrite(busy: "Discarding changes…", failure: "Couldn't discard",
                 done: "Changes discarded", icon: "trash") {
            GitWriter.discardAllChanges(hasCommits: hasCommits, in: repo.path)
        }
    }

    // MARK: - Setting up

    func beginSetup() {
        // Pre-fill from the global git config so a returning user just confirms.
        setupName = gitIdentity?.name ?? ""
        setupEmail = gitIdentity?.email ?? ""
        setupWantsGitignore = true
        setupWantsFirstSave = true
        screen = .setup
    }

    /// Runs every setup step in one go: init, identity, .gitignore, first save.
    func runSetup() {
        guard let repo = activeRepo else { return }
        let name = setupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = setupEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantsGitignore = setupWantsGitignore
        let wantsFirstSave = setupWantsFirstSave
        let alreadyRepo = status.isRepo

        runWrite(busy: "Setting things up…", failure: "Setup didn't finish",
                 done: "All set up", icon: "sparkles") {
            if !alreadyRepo {
                let initialised = GitWriter.initRepo(in: repo.path)
                guard initialised.succeeded else { return initialised }
            }

            if !name.isEmpty && !email.isEmpty {
                let identity = GitWriter.setIdentity(name: name, email: email, in: repo.path)
                guard identity.succeeded else { return identity }
            }

            if wantsGitignore {
                let ignored = GitWriter.writeGitignore(in: repo.path)
                guard ignored.succeeded else { return ignored }
            }

            // The first save comes last so the .gitignore written above is already
            // in force — otherwise the junk it excludes lands in the very first snapshot.
            if wantsFirstSave && GitReader.hasAnythingToSave(in: repo.path) {
                let paths = GitReader.status(of: repo.path).changes.map(\.path)
                let saved = GitWriter.save(paths: paths, message: "first version", in: repo.path)
                guard saved.succeeded else { return saved }
            }

            return ShellResult(status: 0, stdout: "This folder is now yours to save and share.", stderr: "")
        }
    }

    // MARK: - Conflicts

    func beginConflicts() {
        conflicts = status.conflictedFiles.map { ConflictFile(path: $0) }
        screen = .conflicts
    }

    func resolve(_ path: String, as resolution: ConflictFile.Resolution) {
        guard let repo = activeRepo,
              conflicts.contains(where: { $0.path == path }),
              resolution != .undecided
        else { return }

        // git here is a subprocess like any other, so it goes to the shared queue
        // rather than stalling the panel mid-tap.
        Self.gitQueue.async {
            switch resolution {
            case .keepOurs:
                guard GitWriter.keepOurs(path, in: repo.path).succeeded else { return }
            case .keepTheirs:
                guard GitWriter.keepTheirs(path, in: repo.path).succeeded else { return }
            case .editedByHand:
                // Taking the user's word here would stage the `<<<<<<<` markers,
                // which is worse than leaving the file conflicted. Check first.
                guard !GitWriter.stillConflicted(path, in: repo.path) else {
                    DispatchQueue.main.async {
                        self.screen = .result(ActionResult(
                            succeeded: false,
                            title: "Still needs work",
                            detail: "\(path) still has the <<<<<<< and >>>>>>> marker lines in it. Remove them, keep the version you want, save the file, then mark it done."
                        ))
                    }
                    return
                }
            case .undecided:
                return
            }

            guard GitWriter.markResolved(path, in: repo.path).succeeded else { return }

            DispatchQueue.main.async {
                guard self.activeRepo?.id == repo.id,
                      let index = self.conflicts.firstIndex(where: { $0.path == path })
                else { return }
                self.conflicts[index].resolution = resolution
            }
        }
    }

    var allConflictsResolved: Bool {
        !conflicts.isEmpty && conflicts.allSatisfy(\.isResolved)
    }

    func finishConflicts() {
        guard let repo = activeRepo, allConflictsResolved else { return }
        let op = status.mergeOp
        runWrite(busy: "Finishing up…", failure: "Couldn't finish",
                 done: "Sorted", icon: "checkmark") {
            GitWriter.continueOp(op, in: repo.path)
        } onSuccess: { [weak self] in
            self?.conflicts = []
        }
    }

    func abortConflicts() {
        guard let repo = activeRepo else { return }
        let op = status.mergeOp
        runWrite(busy: "Undoing it…", failure: "Couldn't back out",
                 done: "Backed out", icon: "arrow.uturn.backward") {
            GitWriter.abortOp(op, in: repo.path)
        } onSuccess: { [weak self] in
            self?.conflicts = []
        }
    }

    // MARK: - Running writes

    /// Runs one write off the main thread, shows the spinner, then re-reads state.
    ///
    /// On success this lands back on the main screen — the refreshed status
    /// already says what happened ("Everything saved and sent"), so parking on a
    /// separate success card was just an extra tap for no new information. A
    /// failure still gets its own screen, since there's no headline for that.
    ///
    /// `explain` turns a failure into user-facing wording; without it the first
    /// meaningful line of the tool's own output is used.
    ///
    /// `summary` runs on the git queue after a successful write, for actions
    /// whose outcome needs more subprocesses to describe — a grab has to diff
    /// two commits before it can say what arrived. Returning nil means there was
    /// nothing worth a screen. It must not touch main-actor state.
    private func runWrite(
        busy: String,
        failure: String,
        done: String? = nil,
        icon: String = "checkmark",
        summary: (@Sendable () -> ActionResult?)? = nil,
        work: @escaping () -> ShellResult,
        explain: ((ShellResult) -> String)? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        guard !isBusy, let repo = activeRepo else { return }

        isBusy = true
        busyLabel = busy
        screen = .main
        show(PanelActivity(kind: .working, icon: "circle.dashed", text: busy))

        Self.gitQueue.async {
            let result = work()
            let detail = result.succeeded
                ? nil
                : (explain?(result) ?? GitleRunner.firstMeaningfulLine(of: result.message))
            let outcome = result.succeeded ? summary?() : nil
            // Re-read on this queue too; the main thread must not wait on git.
            let (fresh, _, last) = Self.readRepoState(repo.path)

            DispatchQueue.main.async {
                self.isBusy = false
                self.busyLabel = ""
                self.status = fresh
                self.lastSaveMessage = last
                if result.succeeded {
                    // The summary knows more than the generic label does — "Got 3
                    // updates" beats "Up to date" when three actually landed.
                    self.show(PanelActivity(kind: .success, icon: icon, text: outcome?.title ?? done ?? "Done"))
                    if let outcome {
                        self.screen = .result(outcome)
                        self.resultAwaitingReview = true
                    }
                    onSuccess?()
                } else if !self.isBusy, case .main = self.screen {
                    self.show(PanelActivity(kind: .failure, icon: "exclamationmark", text: failure))
                    // onSuccess may have kicked off another write (connect → send)
                    // or routed elsewhere; don't bury that under a failure card —
                    // this only fires when nothing else already claimed the screen.
                    self.screen = .result(ActionResult(succeeded: false, title: failure, detail: detail))
                    self.resultAwaitingReview = true
                }
            }
        }
    }

    /// Publishes a note to the collapsed notch. A `.working` note stays put
    /// until the outcome replaces it; the outcome itself fades on its own.
    private func show(_ next: PanelActivity) {
        activityToken &+= 1
        var note = next
        note.token = activityToken
        withAnimation(Theme.snap) { activity = note }

        guard next.kind != .working else { return }
        let token = activityToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, self.activity?.token == token else { return }
            withAnimation(Theme.snap) { self.activity = nil }
        }

        // A result nobody opened shouldn't still be sitting there an hour later,
        // waiting to greet the next hover with stale news.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self, self.activityToken == token, self.resultAwaitingReview else { return }
            self.resultAwaitingReview = false
            if case .result = self.screen { self.screen = .main }
        }
    }

    /// Routes the panel to a named screen, seeding whatever that screen needs to
    /// have something to draw. Only reachable through the debug notification,
    /// which is off unless `GITLENOCK_DEBUG=1`.
    func jumpToScreen(_ name: String) {
        switch name {
        case "pickFiles": beginSave()
        case "save":
            pickedPaths = Set(status.changes.map(\.path))
            screen = .save
        case "risks":
            pickedPaths = Set(status.changes.map(\.path))
            screen = .risks(SafetyRails.review(paths: Array(pickedPaths), root: activeRepo?.path ?? ""))
        case "files": screen = .files
        case "repos": screen = .repos
        case "confirmSend": screen = .confirmSend
        case "confirmProtectedSend": screen = .confirmProtectedSend(status.branch.isEmpty ? "main" : status.branch)
        case "connect": screen = .connect
        case "setup": beginSetup()
        case "undo": screen = .undo
        case "confirmDiscard": screen = .confirmDiscard
        case "conflicts":
            conflicts = status.changes.prefix(3).map { ConflictFile(path: $0.path) }
            screen = .conflicts
        case "result":
            screen = .result(ActionResult(
                succeeded: false,
                title: "Couldn't send",
                detail: "! [rejected] main -> main (fetch first)\nerror: failed to push some refs"
            ))
        default: screen = .main
        }
    }

    /// Called when the notch collapses, so the next hover starts somewhere sensible.
    func resetTransientScreens() {
        switch screen {
        case .result:
            // An action that finished with the menu shut has its result waiting
            // to be read. Clearing it here would mean hovering after the notch
            // says "Couldn't grab" showed the main menu and no explanation.
            if !resultAwaitingReview { screen = .main }
        case .save, .confirmSend, .pickFiles, .risks,
             .confirmProtectedSend, .connect, .setup, .undo, .confirmDiscard:
            screen = .main
        case .main, .files, .repos, .conflicts:
            // Conflicts survive a collapse: half-resolved state is worth keeping.
            break
        }
    }

    /// Called when the panel opens. Anything waiting to be read has now been
    /// seen, so the next collapse is free to clear it.
    func markResultSeen() {
        resultAwaitingReview = false
    }

    /// A one-slot mailbox for handing a value from a write's `work` closure to
    /// its `summary` closure. Both run on `gitQueue`, one strictly after the
    /// other, so no synchronisation is needed.
    private final class Handoff<T>: @unchecked Sendable {
        var value: T?
    }
}
