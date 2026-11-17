import Foundation

/// A private stdio connection. Thread overrides and MCP credentials stay in this
/// process, and no user configuration file is rewritten.
@MainActor
final class WorkshopCodexRPC {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    var notification: ((String, [String: Any]) -> Void)?

    func start() async throws {
        guard let executable = WorkshopCodexClient.executable else { throw WorkshopError.invalid("请先安装 Codex 并完成登录。") }
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--disable", "shell_tool", "--disable", "apps", "-c", "apps._default.enabled=false", "-c", "web_search=\"disabled\""]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        let directory = Self.directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        process.currentDirectoryURL = directory
        self.process = process; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor in
                guard let self else { return }
                if data.isEmpty { self.close(error: WorkshopError.invalid("Codex 连接已结束。")) }
                else { self.receive(data) }
            }
        }
        do { try process.run() } catch { close(error: error); throw error }
        _ = try await request("initialize", ["clientInfo": ["name": "cliperx_island", "title": "灵剪", "version": "0.3.0"], "capabilities": [:]])
        try write(["method": "initialized"])
    }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.clipnote.app/WidgetWorkshop/Codex", isDirectory: true)
    }
    func request(_ method: String, _ params: [String: Any], timeout: Double = 30) async throws -> [String: Any] {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(["id": id, "method": method, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.pending.removeValue(forKey: id)?.resume(throwing: WorkshopError.invalid("Codex 请求超时，请重试。"))
            }
        }
    }
    private func write(_ value: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw WorkshopError.invalid("Codex 连接不可用。") }
        try input.write(contentsOf: JSONSerialization.data(withJSONObject: value) + Data([10]))
    }
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 67_108_864 else { close(error: WorkshopError.invalid("Codex 返回数据过大。")); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if let id = message["id"] as? Int, message["method"] == nil {
                guard let continuation = pending.removeValue(forKey: id) else { continue }
                if let error = message["error"] as? [String: Any] {
                    continuation.resume(throwing: WorkshopError.invalid(String((error["message"] as? String ?? "Codex 请求失败").prefix(500))))
                } else { continuation.resume(returning: message["result"] as? [String: Any] ?? [:]) }
            } else if let method = message["method"] as? String {
                if let id = message["id"] {
                    // This Q&A surface exposes read-only tools. Interactive permission
                    // requests are rejected so a hidden prompt cannot stall the turn.
                    try? write(["id": id, "error": ["code": -32601, "message": "This client supports read-only Q&A without interactive approvals."]])
                } else { notification?(method, message["params"] as? [String: Any] ?? [:]) }
            }
        }
    }
    func close(error: Error = CancellationError()) {
        output?.readabilityHandler = nil
        let process = process
        self.process = nil
        try? input?.close(); try? output?.close(); input = nil; output = nil
        for continuation in pending.values { continuation.resume(throwing: error) }
        pending.removeAll()
        if process?.isRunning == true {
            process?.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        }
        notification?("cliperx/closed", [:])
        notification = nil
    }
}

@MainActor
final class WorkshopCodexConversation {
    private let rpc = WorkshopCodexRPC()
    private var completion: CheckedContinuation<String, Error>?
    private var completed: Result<String, Error>?
    private var messages: [String: String] = [:]
    private var order: [String] = []
    private var activeThread = ""
    private var lastUpdate = Date.distantPast
    private static var running = Set<String>()

    private func connected<T>(_ body: () async throws -> T) async throws -> T {
        try await withTaskCancellationHandler {
            defer { rpc.close() }
            try await rpc.start()
            return try await body()
        } onCancel: { Task { @MainActor in self.rpc.close() } }
    }
    func threads(cursor: String? = nil, search: String = "") async throws -> WorkshopCodexThreadPage {
        try await connected {
            var params: [String: Any] = ["limit": 30, "sortKey": "updated_at", "sourceKinds": ["cli", "vscode", "exec", "appServer"], "modelProviders": [], "currentAccountOnly": true]
            if let cursor { params["cursor"] = cursor }
            if !search.isEmpty { params["searchTerm"] = search }
            let result = try await rpc.request("thread/list", params)
            return WorkshopCodexThreadPage(threads: try (result["data"] as? [[String: Any]] ?? []).map(WorkshopCodexThread.init), nextCursor: result["nextCursor"] as? String)
        }
    }
    func history(threadID: String, cursor: String? = nil) async throws -> WorkshopCodexHistory {
        try await connected {
            var params: [String: Any] = ["threadId": threadID, "limit": 40, "sortDirection": "desc"]
            // Turns pagination works for both legacy CLI and current paginated threads.
            params["itemsView"] = "full"
            if let cursor { params["cursor"] = cursor }
            let response = try await rpc.request("thread/turns/list", params)
            let turns = response["data"] as? [[String: Any]] ?? []
            var messages: [WorkshopCodexMessage] = []
            var earlierSources: [WorkshopContextSource] = []
            for turn in turns.reversed() {
                let items = turn["items"] as? [[String: Any]] ?? []
                var contexts: [String: WorkshopConversationContext] = [:]
                var sources = earlierSources
                for item in items {
                    if item["type"] as? String == "userMessage", let id = item["id"] as? String {
                        let content = item["content"] as? [[String: Any]] ?? []
                        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                        let imagePaths = content.filter { ["image", "localImage"].contains($0["type"] as? String ?? "") }.map { $0["path"] as? String }
                        if let context = WorkshopConversationContext.userMessage(text, imagePaths: imagePaths) {
                            contexts[id] = context
                            sources = WorkshopConversationContext.merging(context.sources, sources)
                        }
                    }
                    sources = WorkshopConversationContext.merging(sources, WorkshopConversationContext.toolSources(item))
                }
                for item in items {
                    let id = item["id"] as? String ?? UUID().uuidString
                    switch item["type"] as? String {
                    case "userMessage":
                        let content = item["content"] as? [[String: Any]] ?? []
                        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
                        let images = content.filter { ["image", "localImage"].contains($0["type"] as? String ?? "") }.count
                        let context = contexts[id]
                        messages.append(.init(id: id, role: "user", text: String((context?.question ?? text).prefix(30000)), images: images, context: context, sources: sources))
                    case "agentMessage":
                        if let text = item["text"] as? String, !text.isEmpty {
                            messages.append(.init(id: id, role: "assistant", text: String(text.prefix(100000)), images: 0, sources: sources))
                        }
                    default: break
                    }
                }
                earlierSources = sources
            }
            return WorkshopCodexHistory(messages: messages, nextCursor: response["nextCursor"] as? String)
        }
    }
    func answer(thread: WorkshopCodexThread?, input: [[String: Any]], mcp: [String: Any]?,
                onThread: @escaping (WorkshopCodexThread) -> Void,
                onUpdate: @escaping (String, String) -> Void, onSources: @escaping ([WorkshopContextSource]) -> Void = { _ in },
                ephemeral: Bool = false) async throws -> WorkshopCodexReply {
        let lockID = thread?.id ?? UUID().uuidString
        guard !Self.running.contains(lockID) else { throw WorkshopError.invalid("这个 Codex 对话正在回答，请稍后续问。") }
        Self.running.insert(lockID)
        defer { Self.running.remove(lockID) }
        return try await connected {
            let config = try await rpc.request("config/read", ["includeLayers": false])["config"] as? [String: Any] ?? [:]
            var overrides: [String: Any] = ["web_search": "disabled", "features.shell_tool": false, "features.apps": false, "apps._default.enabled": false]
            for name in (config["mcp_servers"] as? [String: Any] ?? [:]).keys {
                overrides["mcp_servers.\(name).enabled"] = false
            }
            for name in (config["plugins"] as? [String: Any] ?? [:]).keys {
                overrides["plugins.\(name).enabled"] = false
            }
            // Explicit per-thread overrides also take precedence over settings saved
            // in a resumed session. The next call rebuilds this map from its switch.
            if let mcp { overrides["mcp_servers.cliperx_island"] = mcp }
            else { overrides["mcp_servers.cliperx_island"] = ["command": "/usr/bin/false", "args": ["--version"], "enabled": false] }
            var params: [String: Any] = ["config": overrides, "approvalPolicy": "never", "sandbox": "read-only"]
            let response: [String: Any]
            if let thread {
                guard !thread.busy else { throw WorkshopError.invalid("这个 Codex 对话正在执行，请稍后选择。") }
                params["threadId"] = thread.id; params["excludeTurns"] = true; params["modelProvider"] = thread.provider
                response = try await rpc.request("thread/resume", params)
            } else {
                params["cwd"] = WorkshopCodexRPC.directory.path
                params["serviceName"] = "cliperx-island"
                params["ephemeral"] = ephemeral
                response = try await rpc.request("thread/start", params)
            }
            guard let value = response["thread"] as? [String: Any] else { throw WorkshopError.invalid("Codex 未返回会话。") }
            let active = try WorkshopCodexThread(value)
            activeThread = active.id
            onThread(active)
            try await prepareClipboardMCP(threadID: active.id, enabled: mcp != nil)
            if mcp != nil { onUpdate("", "灵剪 MCP 已连接") }
            rpc.notification = { [weak self] method, params in self?.receive(method, params, onUpdate: onUpdate, onSources: onSources) }
            _ = try await rpc.request("turn/start", ["threadId": active.id, "input": input])
            let answer = try await waitForAnswer()
            return WorkshopCodexReply(threadID: active.id, text: answer)
        }
    }
    private func prepareClipboardMCP(threadID: String, enabled: Bool) async throws {
        for _ in 0..<40 {
            try Task.checkCancellation()
            let response = try await rpc.request("mcpServerStatus/list", [
                "threadId": threadID, "serverName": "cliperx_island", "detail": "toolsAndAuthOnly"
            ])
            let servers = response["data"] as? [[String: Any]] ?? []
            let server = servers.first { $0["name"] as? String == "cliperx_island" }
            let state = server?["runtimeStatus"] as? String
            let tools = server?["tools"] as? [String: Any] ?? [:]
            if enabled {
                if !tools.isEmpty && (state == "connected" || state == nil) { return }
                if state == "authenticationRequired" { throw WorkshopError.invalid("灵剪 MCP 授权已失效，请重新提问以创建连接。") }
                if state == "failed" || state == "cancelled" { throw WorkshopError.invalid("灵剪 MCP 连接失败，请保持灵剪运行后重试。") }
            } else if server == nil || ["disabled", "notStarted", "cancelled"].contains(state ?? "") || state == nil && tools.isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw WorkshopError.invalid(enabled ? "灵剪 MCP 仍在初始化，请稍后重试。" : "灵剪 MCP 的关闭状态尚未确认，请重试。")
    }
    private var text: String { order.compactMap { messages[$0] }.joined(separator: "\n\n") }
    private func receive(_ method: String, _ params: [String: Any], onUpdate: (String, String) -> Void, onSources: ([WorkshopContextSource]) -> Void) {
        if method == "cliperx/closed" { finish(.failure(CancellationError())); return }
        guard params["threadId"] as? String == activeThread else { return }
        if method == "item/agentMessage/delta", let id = params["itemId"] as? String, let delta = params["delta"] as? String {
            if messages[id] == nil { order.append(id) }
            messages[id, default: ""] += delta
            if text.count > 150000 { finish(.failure(WorkshopError.invalid("回答过长，请缩小问题。"))); rpc.close(); return }
            if Date.now.timeIntervalSince(lastUpdate) > 0.08 { lastUpdate = .now; onUpdate(text, "正在回答…") }
        } else if method == "item/completed", let item = params["item"] as? [String: Any], item["type"] as? String == "agentMessage",
                  let id = item["id"] as? String, let value = item["text"] as? String {
            if messages[id] == nil { order.append(id) }; messages[id] = value
            onUpdate(text, "正在回答…")
        } else if method == "item/completed", let item = params["item"] as? [String: Any], item["type"] as? String == "mcpToolCall" {
            let sources = WorkshopConversationContext.toolSources(item)
            if !sources.isEmpty { onSources(sources) }
        } else if method == "item/started", let item = params["item"] as? [String: Any], item["type"] as? String == "mcpToolCall" {
            onUpdate(text, "正在读取灵剪资料…")
        } else if method == "turn/completed", let turn = params["turn"] as? [String: Any] {
            if turn["status"] as? String == "completed", !text.isEmpty { finish(.success(text)) }
            else {
                let error = (turn["error"] as? [String: Any])?["message"] as? String ?? "Codex 回答已中断，可继续追问。"
                finish(.failure(WorkshopError.invalid(String(error.prefix(500)))))
            }
        }
    }
    private func finish(_ result: Result<String, Error>) {
        if let completion { self.completion = nil; completion.resume(with: result) }
        else if completed == nil { completed = result }
    }
    private func waitForAnswer() async throws -> String {
        if let completed { return try completed.get() }
        return try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(240))
                guard let self, self.completion != nil else { return }
                self.finish(.failure(WorkshopError.invalid("Codex 回答超时，问题和会话已保留。")))
                self.rpc.close()
            }
        }
    }
}
