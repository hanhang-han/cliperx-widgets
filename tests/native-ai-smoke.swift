import Foundation

@main struct WidgetAICoreSmoke {
    static func main() throws {
        let manifestData = Data(#"{"id":"com.cliperx.native-test","name":"Native test","version":"0.1.0","apiVersion":2,"author":"CliperX","description":"Test native capabilities","license":"MIT","symbol":"sparkle","sizes":["wide"],"refreshSeconds":30,"permissions":{"contextPreparation":true}}"#.utf8)
        let manifest = try JSONDecoder().decode(WorkshopManifest.self, from: manifestData)
        try manifest.validate()
        precondition(manifest.permissions.contextPreparation && !manifest.permissions.textProcessing)
        let incompatible = String(decoding: manifestData, as: UTF8.self).replacingOccurrences(of: "\"apiVersion\":2", with: "\"apiVersion\":1")
        do {
            try JSONDecoder().decode(WorkshopManifest.self, from: Data(incompatible.utf8)).validate()
            preconditionFailure("API 1 accepted native permissions")
        } catch {}
        print("PASS API 2 native permission decoding and API 1 compatibility boundary")
        let date = Date(timeIntervalSince1970: 1700000000)
        let first = WorkshopContextMaterial(id: UUID(), title: "设计笔记", source: "Test Editor", date: date, content: "需要保留来源，方便核对。")
        let duplicate = WorkshopContextMaterial(id: UUID(), title: "重复", source: "Test Editor", date: date, content: first.content)
        let long = WorkshopContextMaterial(id: UUID(), title: "长素材", source: "Test Browser", date: date, content: String(repeating: "测试内容", count: 5000))
        let pack = WorkshopContextComposer.compose(task: "整理需求", materials: [first, duplicate, long], budget: 1024, unavailable: 1)
        precondition(pack.count == 2 && pack.shortened == 1 && pack.unavailable == 1)
        precondition(pack.text.contains("[1]") && pack.text.contains("[2]") && pack.text.contains("Test Editor") && pack.text.contains("[已截断]"))
        precondition(pack.estimatedTokens <= 1024)
        for budget in [1024, 2048, 4096, 8192] {
            let full = WorkshopContextComposer.compose(task: String(repeating: "任务", count: 250), materials: [long, first], budget: budget)
            precondition(full.estimatedTokens <= budget)
        }
        print("PASS context provenance, deduplication, budget boundaries and missing-source counts")
        let trimmed = try WorkshopTextTransform.trim.local("  hello  \n world \n")
        precondition(trimmed == "hello\nworld")
        let deduplicated = try WorkshopTextTransform.deduplicate.local("a\nb\na")
        precondition(deduplicated == "a\nb")
        let formatted = try WorkshopTextTransform.json.local("{\"b\":2,\"a\":1}")
        precondition(formatted.contains("\"a\" : 1"))
        do { _ = try WorkshopTextTransform.json.local("broken"); preconditionFailure("Invalid JSON accepted") } catch {}
        print("PASS local text cleanup, deduplication, JSON formatting and invalid input")
        let payload = Data(#"[{"provider":"codex","identity":{"token":"never-forward"},"usage":{"accountEmail":"private@example.com","updatedAt":"2026-11-15T03:00:00Z","primary":null,"secondary":{"usedPercent":6,"windowMinutes":10080,"resetsAt":"2026-11-21T03:00:00Z"}}}]"#.utf8)
        let usage = try WorkshopUsageParser.parse(payload, provider: "codex")
        precondition(usage.windows.count == 1 && usage.windows[0].usedPercent == 6)
        let encoded = String(decoding: try JSONEncoder().encode(usage), as: UTF8.self)
        precondition(!encoded.contains("private@example.com") && !encoded.contains("never-forward"))
        for value in ["null", "[]", "[{\"provider\":\"codex\",\"usage\":{\"primary\":{\"usedPercent\":101}}}]"] {
            do { _ = try WorkshopUsageParser.parse(Data(value.utf8), provider: "codex"); preconditionFailure("Invalid quota accepted") } catch {}
        }
        print("PASS real CodexBar schema, null primary window, secret stripping and invalid quota rejection")
        var events = WorkshopCodexEvents()
        let thread = UUID().uuidString
        try events.accept(JSONSerialization.data(withJSONObject: ["type": "thread.started", "thread_id": thread]))
        try events.accept(Data(#"{"type":"item.completed","item":{"type":"agent_message","text":"synthetic reply"}}"#.utf8))
        try events.accept(Data(#"{"type":"turn.completed"}"#.utf8))
        precondition(events.threadID == thread && events.text == "synthetic reply" && events.completed)
        var failure = WorkshopCodexEvents()
        try failure.accept(Data(#"{"type":"turn.failed","error":{"message":"synthetic failure"}}"#.utf8))
        precondition(failure.error == "synthetic failure" && !failure.completed)
        print("PASS Codex completion receipts, thread identifiers and failure events")
    }
}
