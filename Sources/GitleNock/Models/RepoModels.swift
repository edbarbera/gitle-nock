import Foundation

/// A folder the user has added to the notch menu.
struct Repo: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String

    init(id: UUID = UUID(), path: String) {
        self.id = id
        self.path = path
    }

    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// One file git reports as changed, in the vocabulary gitle uses.
struct FileChange: Identifiable, Hashable {
    enum Kind: String {
        case new = "New"
        case changed = "Changed"
        case deleted = "Deleted"
        case renamed = "Renamed"

        var symbol: String {
            switch self {
            case .new: return "plus.circle.fill"
            case .changed: return "pencil.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .renamed: return "arrow.triangle.turn.up.right.circle.fill"
            }
        }
    }

    var id: String { path }
    let kind: Kind
    let path: String

    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// A half-finished merge, rebase or cherry-pick. Conflicts can only be talked
/// about in terms of one of these, because which side counts as "yours" flips
/// between them.
enum MergeOp: Equatable {
    case none
    case merge
    case rebase
    case cherryPick

    /// Plain-English names for the two sides of a conflict. In a merge or
    /// cherry-pick HEAD is the user's own work; in a rebase their commits are
    /// the ones being replayed on top of HEAD, so the meaning flips.
    var sideLabels: (ours: String, theirs: String) {
        switch self {
        case .rebase: return ("what's already there", "your changes")
        case .cherryPick: return ("your version", "the commit you're bringing in")
        default: return ("your version", "the version you grabbed")
        }
    }

    var verb: String {
        switch self {
        case .rebase: return "grab"
        case .cherryPick: return "copy"
        default: return "merge"
        }
    }
}

/// One file git can't merge on its own, plus what the user decided about it.
struct ConflictFile: Identifiable, Equatable {
    enum Resolution: Equatable {
        case undecided
        case keepOurs
        case keepTheirs
        case editedByHand
    }

    var id: String { path }
    let path: String
    var resolution: Resolution = .undecided

    var filename: String { URL(fileURLWithPath: path).lastPathComponent }
    var isResolved: Bool { resolution != .undecided }
}

/// What `SafetyRails.review` found in the files about to be saved. An empty
/// report means there's nothing worth stopping the user for.
struct RiskReport: Equatable {
    struct LargeFile: Equatable {
        let path: String
        let size: Int64
    }

    var secrets: [String] = []
    var large: [LargeFile] = []

    var isEmpty: Bool { secrets.isEmpty && large.isEmpty }

    /// Every flagged path, so the user can drop them all in one tap.
    var allPaths: [String] { secrets + large.map(\.path) }
}

/// Everything the menu needs to know about a repo, read straight from git.
struct RepoStatus: Equatable {
    var isRepo: Bool = false
    var branch: String = ""
    var changes: [FileChange] = []
    var ahead: Int = 0
    var behind: Int = 0
    var hasRemote: Bool = false
    var hasUpstream: Bool = false
    var hasCommits: Bool = false
    /// A merge/rebase/cherry-pick left half-finished by a clashing grab.
    var mergeOp: MergeOp = .none
    var conflictedFiles: [String] = []
    /// The folder is a repo, but macOS blocked us from reading it.
    var accessDenied: Bool = false

    static let empty = RepoStatus()

    var isClean: Bool { changes.isEmpty }

    var hasConflicts: Bool { !conflictedFiles.isEmpty }

    /// The single most useful thing to tell the user right now, in plain English.
    var headline: String {
        if accessDenied { return "Can't open this folder" }
        if !isRepo { return "Not set up yet" }
        // Conflicts outrank everything: nothing else can proceed until they're fixed.
        if hasConflicts {
            let plural = conflictedFiles.count == 1
            return "\(conflictedFiles.count) file\(plural ? "" : "s") need\(plural ? "s" : "") your help"
        }
        if behind > 0 && !isClean { return "\(changes.count) unsaved · \(behind) waiting online" }
        if behind > 0 { return "\(behind) update\(behind == 1 ? "" : "s") waiting online" }
        if !isClean { return "\(changes.count) unsaved change\(changes.count == 1 ? "" : "s")" }
        if ahead > 0 { return "\(ahead) save\(ahead == 1 ? "" : "s") not sent yet" }
        return "Everything saved and sent"
    }
}
