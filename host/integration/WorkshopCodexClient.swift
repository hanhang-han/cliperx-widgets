import Foundation

struct WorkshopCodexReply: Sendable {
    let threadID: String?
    let text: String
}

/// Each invocation has its own process, cancellation and output budget.
final class WorkshopCodexProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        Self.stop(running)
    }
    private static func stop(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    func run(prompt: String, threadID: String?, ephemeral: Bool) throws -> WorkshopCodexReply {
        guard let executable = WorkshopCodexClient.executable else {
            throw WorkshopError.invalid("请安装 Codex，并在 Codex 中完成登录。")
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.clipnote.app/WidgetWorkshop/Codex", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let task = Process(), input = Pipe(), output = Pipe()
        task.executableURL = executable
        var arguments = ["exec", "--ignore-user-config", "--json", "--skip-git-repo-check",
                         "--disable", "shell_tool", "-c", "web_search=\"disabled\"", "-c", "sandbox_mode=\"read-only\"",
                         "-c", "approval_policy=\"never\"", "-C", directory.path]
        if let threadID {
            guard UUID(uuidString: threadID) != nil else { throw WorkshopError.invalid("Codex 会话标识无效，请新建对话。") }
            arguments += ["resume", threadID]
        }
        if ephemeral { arguments.append("--ephemeral") }
        arguments.append("-")
        task.arguments = arguments
        task.currentDirectoryURL = directory
        task.standardInput = input
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try task.run() } catch { lock.unlock(); throw error }
        process = task
        lock.unlock()
        let deadline = DispatchWorkItem { Self.stop(task) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180, execute: deadline)
        defer {
            deadline.cancel()
            Self.stop(task)
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        try input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        try input.fileHandleForWriting.close()
        var parser = WorkshopCodexEvents()
        var buffer = Data(), received = 0
        while true {
            let chunk = output.fileHandleForReading.readData(ofLength: 8192)
            if chunk.isEmpty { break }
            received += chunk.count
            guard received <= 4_194_304 else { throw WorkshopError.invalid("Codex 输出超过上限，请缩小任务后重试。") }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                try parser.accept(line)
            }
        }
        if !buffer.isEmpty { try parser.accept(buffer) }
        task.waitUntilExit()
        lock.lock()
        let wasCancelled = cancelled
        process = nil
        lock.unlock()
        if wasCancelled { throw CancellationError() }
        if let error = parser.error { throw WorkshopError.invalid(error) }
        guard task.terminationStatus == 0, parser.completed, !parser.text.isEmpty else {
            throw WorkshopError.invalid("Codex 调用中断或超时，已保留问题与选材。请检查 Codex 登录和网络连接。")
        }
        return WorkshopCodexReply(threadID: parser.threadID ?? threadID, text: parser.text)
    }
}

enum WorkshopCodexClient {
    static var executable: URL? {
        let paths = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                     "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/codex" }
        return (paths + fromPath).first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }
    static func send(_ prompt: String, threadID: String? = nil, ephemeral: Bool = false) async throws -> WorkshopCodexReply {
        let runner = WorkshopCodexProcess()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) { try runner.run(prompt: prompt, threadID: threadID, ephemeral: ephemeral) }.value
        } onCancel: { runner.cancel() }
    }
}
