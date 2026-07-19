import Foundation

/// Runs the `gitle` CLI for anything that changes the repo.
///
/// Every safety rail (secret detection, big-file warnings, the push-to-main nudge)
/// lives in gitle, so mutations go through it rather than raw git.
enum GitleRunner {
    enum Action {
        case save(message: String)
        case send
        case grab

        var arguments: [String] {
            switch self {
            // --all skips the interactive file checklist, which can't be answered
            // from a subprocess. Per-file picking belongs in the notch UI later.
            case .save(let message): return ["save", "--all", message]
            case .send: return ["send"]
            case .grab: return ["grab"]
            }
        }

        var runningLabel: String {
            switch self {
            case .save: return "Saving your work…"
            case .send: return "Sending it online…"
            case .grab: return "Grabbing the latest…"
            }
        }

        var successLabel: String {
            switch self {
            case .save: return "Saved."
            case .send: return "Sent online."
            case .grab: return "Got the latest."
            }
        }
    }

    static var gitlePath: String? { Shell.which("gitle") }

    static var isInstalled: Bool { gitlePath != nil }

    static func run(_ action: Action, in path: String) -> ShellResult {
        guard let gitlePath else {
            return ShellResult(
                status: -1,
                stdout: "",
                stderr: "gitle isn't installed yet. Install it, then try again."
            )
        }
        return Shell.run(gitlePath, action.arguments, in: path)
    }

    /// gitle writes friendly prose with box-drawing and emoji. Strip the decoration
    /// so the notch can show a single readable line.
    static func firstMeaningfulLine(of output: String) -> String? {
        let noise = CharacterSet(charactersIn: "✓✗⚠️🔒📦🌿🔄🧩🤖→·—-=[](){}⏎ \t")
        for line in output.split(separator: "\n") {
            let cleaned = String(line)
                .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                .trimmingCharacters(in: noise)
            if cleaned.count > 2 { return cleaned }
        }
        return nil
    }
}
