import Foundation

/// Runs the `gitle` CLI.
///
/// Only `grab` is left here. gitle's other commands all pause on a terminal
/// prompt — a file checklist, "save these anyway?", "send to main anyway?" —
/// and a prompt can't be answered from a headless subprocess, so gitle took its
/// safe default and the action silently did nothing. Those questions are asked
/// in the notch now and the underlying git command runs from `GitWriter`.
/// `grab` has no prompts, so it still works exactly as the CLI does.
enum GitleRunner {
    enum Action {
        case grab

        var arguments: [String] {
            switch self {
            case .grab: return ["grab"]
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
