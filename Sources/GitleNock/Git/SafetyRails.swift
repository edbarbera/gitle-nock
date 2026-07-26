import Foundation

/// The checks that used to live behind gitle's terminal prompts.
///
/// gitle asks these questions with `ui.Confirm`, which needs a real TTY. The
/// notch runs it headless, so the questions never reached the user — they were
/// answered with the safe default and the action aborted. The app now owns the
/// checks and asks them in the panel instead. Kept deliberately in step with
/// `cmd/safety.go` and `cmd/gitignore.go` in the gitle repo.
enum SafetyRails {
    /// Size above which a file is likely build output, video or a dataset
    /// rather than something that belongs in version control.
    static let largeFileBytes: Int64 = 10 * 1024 * 1024

    /// Filenames that commonly hold passwords, keys or tokens. Committing one —
    /// especially then sending it online — leaks credentials.
    static let secretGlobs = [
        ".env", ".env.*",
        "*.pem", "*.key", "*.p12", "*.pfx", "*.keystore", "*.crt",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        "credentials.json", ".npmrc", ".pypirc"
    ]

    /// Shared lines of work where pushing directly is worth pausing on.
    static let protectedBranches: Set<String> = ["main", "master"]

    static func isProtected(_ branch: String) -> Bool { protectedBranches.contains(branch) }

    static func looksLikeSecret(_ path: String) -> Bool {
        let base = (path as NSString).lastPathComponent
        return secretGlobs.contains { pattern in
            fnmatch(pattern, base, 0) == 0
        }
    }

    /// Inspects the files about to be saved. An empty report means nothing to ask about.
    static func review(paths: [String], root: String) -> RiskReport {
        var secrets: [String] = []
        var large: [RiskReport.LargeFile] = []

        for path in paths {
            if looksLikeSecret(path) { secrets.append(path) }

            let full = (root as NSString).appendingPathComponent(path)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: full),
                  (attrs[.type] as? FileAttributeType) != .typeDirectory,
                  let size = attrs[.size] as? Int64,
                  size > largeFileBytes
            else { continue }
            large.append(RiskReport.LargeFile(path: path, size: size))
        }

        return RiskReport(secrets: secrets, large: large)
    }

    static func humanSize(_ bytes: Int64) -> String {
        let byteCount = Double(bytes)
        if bytes >= 1 << 30 { return String(format: "%.1f GB", byteCount / Double(1 << 30)) }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", byteCount / Double(1 << 20)) }
        if bytes >= 1 << 10 { return String(format: "%.1f KB", byteCount / Double(1 << 10)) }
        return "\(bytes) B"
    }

    // MARK: - .gitignore starters

    /// Added for every project: OS cruft, logs, and the secret files that should
    /// never be shared.
    private static let gitignoreCommon = """
    # OS files
    .DS_Store
    Thumbs.db

    # Logs
    *.log

    # Secrets — never share these
    .env
    .env.local
    .env.*.local

    """

    struct ProjectKind {
        let name: String
        let body: String
        let matched: Bool

        var gitignore: String {
            body.isEmpty ? gitignoreCommon : body + "\n" + gitignoreCommon
        }
    }

    /// A project kind is recognised by any exact filename in `names` or any
    /// file with a suffix in `suffixes` sitting in the project root.
    private struct ProjectMarkers {
        let names: [String]
        let suffixes: [String]
        let kind: ProjectKind
    }

    private static let projectMarkers: [ProjectMarkers] = [
        ProjectMarkers(
            names: ["package.json"], suffixes: [],
            kind: ProjectKind(
                name: "Node.js",
                body: "# Node\nnode_modules/\ndist/\nbuild/\ncoverage/\n.next/\n.turbo/\n",
                matched: true
            )
        ),
        ProjectMarkers(
            names: ["requirements.txt", "pyproject.toml", "setup.py", "Pipfile"], suffixes: [],
            kind: ProjectKind(
                name: "Python",
                body: "# Python\n__pycache__/\n*.pyc\n.venv/\nvenv/\n*.egg-info/\n.pytest_cache/\n.mypy_cache/\n",
                matched: true
            )
        ),
        ProjectMarkers(
            names: ["go.mod"], suffixes: [],
            kind: ProjectKind(name: "Go", body: "# Go\n/bin/\n*.exe\n*.test\n", matched: true)
        ),
        ProjectMarkers(
            names: ["Cargo.toml"], suffixes: [],
            kind: ProjectKind(name: "Rust", body: "# Rust\n/target/\n", matched: true)
        ),
        ProjectMarkers(
            names: ["Gemfile"], suffixes: [],
            kind: ProjectKind(name: "Ruby", body: "# Ruby\n*.gem\n/.bundle/\nvendor/bundle/\n", matched: true)
        ),
        ProjectMarkers(
            names: ["pom.xml", "build.gradle", "build.gradle.kts"], suffixes: [],
            kind: ProjectKind(name: "Java", body: "# Java\n*.class\ntarget/\nbuild/\n.gradle/\n", matched: true)
        ),
        ProjectMarkers(
            names: [], suffixes: [".csproj", ".sln", ".fsproj"],
            kind: ProjectKind(name: ".NET", body: "# .NET\nbin/\nobj/\n*.user\n", matched: true)
        ),
        ProjectMarkers(
            names: ["composer.json"], suffixes: [],
            kind: ProjectKind(name: "PHP", body: "# PHP\n/vendor/\ncomposer.phar\n", matched: true)
        ),
        ProjectMarkers(
            names: ["Package.swift"], suffixes: [".xcodeproj"],
            kind: ProjectKind(
                name: "Swift", body: "# Swift\n.build/\nDerivedData/\nxcuserdata/\nPackages/\n", matched: true
            )
        ),
        ProjectMarkers(
            names: ["mix.exs"], suffixes: [],
            kind: ProjectKind(name: "Elixir", body: "# Elixir\n_build/\ndeps/\n*.ez\n", matched: true)
        ),
        ProjectMarkers(
            names: ["pubspec.yaml"], suffixes: [],
            kind: ProjectKind(
                name: "Dart/Flutter", body: "# Dart/Flutter\n.dart_tool/\nbuild/\n.packages\n", matched: true
            )
        )
    ]

    /// Sniffs a folder for tell-tale files to pick a .gitignore starting point.
    static func detectProject(in root: String) -> ProjectKind {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        func has(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent(name))
        }

        for markers in projectMarkers {
            if markers.names.contains(where: has) { return markers.kind }
            if entries.contains(where: { entry in markers.suffixes.contains { entry.hasSuffix($0) } }) {
                return markers.kind
            }
        }
        return ProjectKind(name: "this folder", body: "", matched: false)
    }
}
