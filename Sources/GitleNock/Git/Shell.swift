import Foundation

struct ShellResult {
    let status: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { status == 0 }

    /// stderr first — tools put the interesting failure there — falling back to stdout.
    var message: String {
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !err.isEmpty { return err }
        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Shell {
    /// GUI apps inherit a bare PATH, so look in the places CLI tools actually land.
    static let searchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        NSString(string: "~/.local/bin").expandingTildeInPath,
        NSString(string: "~/bin").expandingTildeInPath
    ]

    static func which(_ tool: String) -> String? {
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(tool)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    static func run(
        _ launchPath: String,
        _ arguments: [String],
        in directory: String? = nil,
        timeout: TimeInterval = 20
    ) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = URL(fileURLWithPath: directory) }

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        // Keep gitle and git non-interactive: a prompt in a headless subprocess hangs forever.
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["NO_COLOR"] = "1"
        env["CI"] = "1"
        process.environment = env

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes at the same time. Reading one to EOF before touching the
        // other deadlocks as soon as the child fills the pipe it isn't being read
        // from — the child blocks on write, we block on read, nobody moves.
        let sink = OutputSink()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "gitlenock.shell.read", attributes: .concurrent)

        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }

        queue.async(group: group) { sink.appendOut(out.fileHandleForReading.readDataToEndOfFile()) }
        queue.async(group: group) { sink.appendErr(err.fileHandleForReading.readDataToEndOfFile()) }

        // A wedged subprocess must not wedge the app. git waiting on a credential
        // prompt or a lock file is the realistic case.
        if process.isRunning, group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + 2)
            process.waitUntilExit()
            return ShellResult(status: -1, stdout: sink.stdout, stderr: "Timed out after \(Int(timeout))s.")
        }

        group.wait()
        process.waitUntilExit()

        return ShellResult(status: process.terminationStatus, stdout: sink.stdout, stderr: sink.stderr)
    }
}

/// Collects pipe output from two reader threads.
private final class OutputSink: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()

    func appendOut(_ data: Data) { lock.lock(); outData.append(data); lock.unlock() }
    func appendErr(_ data: Data) { lock.lock(); errData.append(data); lock.unlock() }

    // Subprocess output can contain non-UTF8 bytes (odd filenames, binary diffs).
    // The failable `String(bytes:encoding:)` would turn that into an empty
    // string and hide real output, so the lossy replacement-character decode
    // is intentional here, not an oversight.
    // swiftlint:disable:next optional_data_string_conversion
    var stdout: String { lock.lock(); defer { lock.unlock() }; return String(decoding: outData, as: UTF8.self) }
    // swiftlint:disable:next optional_data_string_conversion
    var stderr: String { lock.lock(); defer { lock.unlock() }; return String(decoding: errData, as: UTF8.self) }
}
