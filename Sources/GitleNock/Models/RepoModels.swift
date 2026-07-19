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
    /// The folder is a repo, but macOS blocked us from reading it.
    var accessDenied: Bool = false

    static let empty = RepoStatus()

    var isClean: Bool { changes.isEmpty }

    /// The single most useful thing to tell the user right now, in plain English.
    var headline: String {
        if accessDenied { return "Can't open this folder" }
        if !isRepo { return "Not set up yet" }
        if behind > 0 && !isClean { return "\(changes.count) unsaved · \(behind) waiting online" }
        if behind > 0 { return "\(behind) update\(behind == 1 ? "" : "s") waiting online" }
        if !isClean { return "\(changes.count) unsaved change\(changes.count == 1 ? "" : "s")" }
        if ahead > 0 { return "\(ahead) save\(ahead == 1 ? "" : "s") not sent yet" }
        return "Everything saved and sent"
    }
}
