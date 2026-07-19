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
        "credentials.json", ".npmrc", ".pypirc",
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
        let b = Double(bytes)
        if bytes >= 1 << 30 { return String(format: "%.1f GB", b / Double(1 << 30)) }
        if bytes >= 1 << 20 { return String(format: "%.1f MB", b / Double(1 << 20)) }
        if bytes >= 1 << 10 { return String(format: "%.1f KB", b / Double(1 << 10)) }
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

    /// Sniffs a folder for tell-tale files to pick a .gitignore starting point.
    static func detectProject(in root: String) -> ProjectKind {
        func has(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent(name))
        }
        func hasSuffix(_ ext: String) -> Bool {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return false }
            return entries.contains { $0.hasSuffix(ext) }
        }

        if has("package.json") {
            return ProjectKind(name: "Node.js", body: "# Node\nnode_modules/\ndist/\nbuild/\ncoverage/\n.next/\n.turbo/\n", matched: true)
        }
        if has("requirements.txt") || has("pyproject.toml") || has("setup.py") || has("Pipfile") {
            return ProjectKind(name: "Python", body: "# Python\n__pycache__/\n*.pyc\n.venv/\nvenv/\n*.egg-info/\n.pytest_cache/\n.mypy_cache/\n", matched: true)
        }
        if has("go.mod") {
            return ProjectKind(name: "Go", body: "# Go\n/bin/\n*.exe\n*.test\n", matched: true)
        }
        if has("Cargo.toml") {
            return ProjectKind(name: "Rust", body: "# Rust\n/target/\n", matched: true)
        }
        if has("Gemfile") {
            return ProjectKind(name: "Ruby", body: "# Ruby\n*.gem\n/.bundle/\nvendor/bundle/\n", matched: true)
        }
        if has("pom.xml") || has("build.gradle") || has("build.gradle.kts") {
            return ProjectKind(name: "Java", body: "# Java\n*.class\ntarget/\nbuild/\n.gradle/\n", matched: true)
        }
        if hasSuffix(".csproj") || hasSuffix(".sln") || hasSuffix(".fsproj") {
            return ProjectKind(name: ".NET", body: "# .NET\nbin/\nobj/\n*.user\n", matched: true)
        }
        if has("composer.json") {
            return ProjectKind(name: "PHP", body: "# PHP\n/vendor/\ncomposer.phar\n", matched: true)
        }
        if has("Package.swift") || hasSuffix(".xcodeproj") {
            return ProjectKind(name: "Swift", body: "# Swift\n.build/\nDerivedData/\nxcuserdata/\nPackages/\n", matched: true)
        }
        if has("mix.exs") {
            return ProjectKind(name: "Elixir", body: "# Elixir\n_build/\ndeps/\n*.ez\n", matched: true)
        }
        if has("pubspec.yaml") {
            return ProjectKind(name: "Dart/Flutter", body: "# Dart/Flutter\n.dart_tool/\nbuild/\n.packages\n", matched: true)
        }
        return ProjectKind(name: "this folder", body: "", matched: false)
    }
}
