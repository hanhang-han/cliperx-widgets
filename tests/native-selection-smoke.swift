import AppKit
import Combine
import Foundation

@MainActor final class ClipboardMonitor {
    static let shared = ClipboardMonitor()
    var blockAutoCollapse = false
    var clipboardWritingActive = false
    enum State { case compact }
    func transition(to state: State) {}
    func showToast(_ text: String, duration: TimeInterval = 1) {}
}
@MainActor final class SettingsManager {
    static let shared = SettingsManager()
    var islandPanelHeight = 400.0
}
@MainActor final class AppDelegate {
    static var shared: AppDelegate?
    var panel: NSPanel?
    func resizeIslandWorkspace() {}
}
@MainActor enum ScreenHelper { static func targetScreen() -> NSScreen? { nil } }
@MainActor final class IslandWorkspaceState {
    enum Page { case clipboard, settings }
    static let shared = IslandWorkspaceState()
    var page = Page.clipboard
    var clipboardExpanded = false
    var preferredHeight: CGFloat { 280 }
    func show(_ page: Page) { self.page = page }
}
enum StubKind: Equatable { case community(String) }
struct StubWidget { let id: UUID; let kind: StubKind }
@MainActor final class IslandWidgetPreferences {
    static let shared = IslandWidgetPreferences()
    var configuration = StubConfiguration()
}
struct StubConfiguration { var widgets: [StubWidget] = [] }
@MainActor final class ClipboardLibrary {
    static let shared = ClipboardLibrary()
    var materials: [UUID: WorkshopContextMaterial] = [:]
    var saved: [String] = []
    func widgetContextMaterial(id: UUID, includeImages: Bool = false) throws -> WorkshopContextMaterial {
        guard let material = materials[id], includeImages || material.imageData == nil else { throw WorkshopError.invalid("missing source") }
        return material
    }
    func createItem(content: String) throws { saved.append(content) }
}
enum ClipboardAIPrivacy { static func isSensitive(_ text: String) -> Bool { text.contains("synthetic-secret") } }
enum WorkshopModelKeychain { static func load(_ endpoint: String) -> String { "" } }
struct WorkshopModelConfiguration {
    let provider: String
    let endpoint: String
    let model: String
    let secret: String
    func generate(action: WorkshopTextTransform, input: String, instruction: String, onUpdate: @escaping @MainActor (String) -> Void = { _ in }) async throws -> String {
        if action.needsModel { return "synthetic model output" }
        return try action.local(input)
    }
}
struct WorkshopCodexReply { let threadID: String?; let text: String }
@MainActor enum WorkshopCodexClient {
    static var prompts: [String] = []
    static func send(_ prompt: String, threadID: String? = nil, ephemeral: Bool = false) async throws -> WorkshopCodexReply {
        prompts.append(prompt)
        try await Task.sleep(nanoseconds: 80_000_000)
        return .init(threadID: threadID ?? UUID().uuidString, text: "synthetic response")
    }
}

@MainActor final class WorkshopContextAccess {
    func open() async throws -> [String: Any] { ["enabled": true] }
    func close() {}
}
enum WorkshopContextInput {
    static func make(question: String, materials: [WorkshopContextMaterial], budget: Int, useMCP: Bool) throws -> [[String: Any]] {
        [["text": question + materials.map(\.content).joined(separator: "\n"), "imageCount": materials.filter { $0.imageData != nil }.count]]
    }
}
@MainActor final class WorkshopCodexConversation {
    static var inputs: [[[String: Any]]] = []
    static var resumed: [String?] = []
    static var mcp: [Bool] = []
    func history(threadID: String, cursor: String? = nil) async throws -> WorkshopCodexHistory {
        .init(messages: [.init(id: "history-user", role: "user", text: "earlier question", images: 0),
                         .init(id: "history-answer", role: "assistant", text: "earlier answer", images: 1)], nextCursor: nil)
    }
    func answer(thread: WorkshopCodexThread?, input: [[String: Any]], mcp: [String: Any]?, onThread: @escaping (WorkshopCodexThread) -> Void, onUpdate: @escaping (String, String) -> Void, onSources: @escaping ([WorkshopContextSource]) -> Void = { _ in }) async throws -> WorkshopCodexReply {
        Self.inputs.append(input); Self.resumed.append(thread?.id); Self.mcp.append(mcp != nil)
        let thread = try thread ?? WorkshopCodexThread(["id": UUID().uuidString, "name": "Synthetic conversation"])
        onThread(thread)
        onUpdate("streamed", "正在回答")
        try await Task.sleep(nanoseconds: 80_000_000)
        return .init(threadID: thread.id, text: "synthetic answer")
    }
}

@main struct IslandAISelectionSmoke {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let library = ClipboardLibrary.shared
        let first = WorkshopContextMaterial(id: UUID(), title: "first", source: "Fixture", date: .now, content: "first\nrepeat\nrepeat")
        let second = WorkshopContextMaterial(id: UUID(), title: "second", source: "Fixture", date: .now, content: "second\nother\nother")
        library.materials = [first.id: first, second.id: second]
        let context = IslandAISession(id: UUID(), mode: .context, directory: directory)
        context.toggle(first)
        context.question = "Use the first material"
        context.send()
        context.toggle(second)
        context.question = "Next question stays in the draft"
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(context.turns.count == 1 && context.turns[0].isComplete && context.turns[0].answer == "synthetic answer")
        precondition(context.selected == [second.id] && context.question == "Next question stays in the draft")
        precondition(WorkshopCodexConversation.inputs.count == 1 && !(WorkshopCodexConversation.inputs[0][0]["text"] as! String).contains(second.content))
        precondition(context.turns[0].attachments.map(\.id) == [first.id] && context.hasResults)
        context.flushDraft()
        let restored = IslandAISession(id: context.id, mode: .context, directory: directory)
        precondition(restored.selected == context.selected && restored.question == context.question && restored.conversation?.id == context.conversation?.id && !restored.useMCP)
        print("PASS frozen question attachments, island answer, next-question edits and durable conversation restoration")

        let historyThread = try WorkshopCodexThread(["id": UUID().uuidString, "name": "Selected real-style history", "modelProvider": "openai"])
        context.selectConversation(historyThread)
        try await Task.sleep(nanoseconds: 20_000_000)
        precondition(context.historyMessages.count == 2 && context.turns.isEmpty)
        context.clearSelection(); context.question = "Follow up on that answer"; context.useMCP = true
        precondition(context.canSend)
        context.send()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(WorkshopCodexConversation.resumed.last! == historyThread.id && WorkshopCodexConversation.mcp.last == true)
        context.question = "One more"; context.useMCP = false; context.send()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(WorkshopCodexConversation.mcp.last == false && context.turns.count == 2)
        context.newConversation()
        precondition(context.conversation == nil && context.historyMessages.isEmpty && context.turns.isEmpty)
        let image = WorkshopContextMaterial(id: UUID(), title: "image", source: "Fixture", date: .now, content: "[图片]", imageData: Data([1]))
        library.materials[image.id] = image
        context.toggle(image); context.question = "What is in the image?"; context.send()
        try await Task.sleep(nanoseconds: 150_000_000)
        precondition(WorkshopCodexConversation.inputs.last![0]["imageCount"] as? Int == 1 && context.turns.last?.attachments.first?.isImage == true)
        print("PASS historical conversation selection/resume, question-only followups, per-call MCP toggle and image attachments")

        let text = IslandAISession(id: UUID(), mode: .text, directory: directory)
        text.action = .deduplicate
        text.toggle(first); text.toggle(second)
        try await Task.sleep(nanoseconds: 50_000_000)
        precondition(text.results.count == 1 && text.results[0].output == "second\nother" && text.selected == [second.id])
        precondition(library.materials[first.id]?.content == first.content)
        text.saveResult()
        precondition(library.saved == ["second\nother"])
        print("PASS immediate single-card processing, original preservation and explicit new-item save")

        context.toggle(first)
        library.materials.removeValue(forKey: first.id)
        context.send()
        precondition(context.unavailable == 1 && !context.canSend && context.feedback.contains("失效"))
        context.remove(first.id)
        precondition(context.unavailable == 0)
        print("PASS deleted sources are revalidated before sending and can be removed from selection")

        let id = UUID(), workspace = IslandAIWorkspace(draftDirectory: directory)
        workspace.toggle(id: id, mode: .context)
        let contextMode = workspace.active!
        workspace.toggle(id: id, mode: .text)
        precondition(workspace.active?.mode == .text && workspace.active !== contextMode)
        workspace.toggle(id: id, mode: .text)
        precondition(workspace.active == nil)
        workspace.toggle(id: id, mode: .context)
        precondition(workspace.active === contextMode)
        var dismissed = false
        let popoverID = UUID()
        workspace.presentPopover(id: popoverID) { dismissed = true }
        precondition(workspace.dismissPresentedPopover() && dismissed && workspace.active === contextMode)
        precondition(!workspace.dismissPresentedPopover())
        print("PASS isolated mode drafts, repeat-click exit, popover-first dismissal and return-to-mode restoration")
    }
}
