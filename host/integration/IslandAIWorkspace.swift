import AppKit
import Combine
import Foundation
import SwiftUI

private enum IslandAIPhase: String, Codable { case working, complete, failed, stopped }
enum IslandAIMode: String, Codable, Hashable { case context, text }

struct IslandAIAttachment: Codable, Identifiable {
    let id: UUID
    let title: String
    let source: String
    var isImage: Bool? = nil
}
struct IslandAITurn: Codable, Identifiable {
    let id: UUID
    let question: String
    let attachments: [IslandAIAttachment]
    var answer = ""
    var error = ""
    var sources: [WorkshopContextSource]? = nil
    var taskQuestion: String? = nil
    fileprivate var phase: IslandAIPhase = .working
    var isWorking: Bool { phase == .working }
    var isComplete: Bool { phase == .complete }
    var attachmentContext: WorkshopConversationContext {
        var textNumber = 0
        var imageNumber = 0
        let selectedSources = attachments.map { attachment -> WorkshopContextSource in
            if attachment.isImage == true { imageNumber += 1 }
            else { textNumber += 1 }
            if let source = sources?.first(where: { $0.clipboardID == attachment.id }) { return source }
            return .init(clipboardID: attachment.id, label: attachment.isImage == true ? "图\(imageNumber)" : String(textNumber),
                         title: attachment.title, source: attachment.source, isImage: attachment.isImage == true)
        }
        return .init(question: question, sources: selectedSources)
    }
    var answerSources: [WorkshopContextSource] { sources ?? attachmentContext.sources }

}
struct IslandAITextResult: Codable, Identifiable {
    let id: UUID
    let title: String
    let original: String
    var output = ""
    var error = ""
    var cacheKey: String? = nil
    fileprivate var phase: IslandAIPhase = .working
    var isWorking: Bool { phase == .working }
    var isComplete: Bool { phase == .complete }
}

private struct IslandAIDraft: Codable {
    var selected: [UUID] = []
    var question = ""
    var target = "codex"
    var action: String = "rewrite"
    var instruction = ""
    var budget = 4096
    var turns: [IslandAITurn] = []
    var results: [IslandAITextResult] = []
    var threadID: String?
    var conversation: WorkshopCodexThread?
    var translationLanguage: String? = nil
    var textPreferencesVersion: Int? = nil
    var endpoint: String? = nil
    var model: String? = nil
    var activeTextResultID: UUID? = nil
    var taskParameters: [String: String]? = nil
}

@MainActor
final class IslandAISession: ObservableObject {
    let id: UUID
    let mode: IslandAIMode
    @Published var selected: [UUID] = []
    @Published var question = ""
    @Published var target = "codex"
    @Published var useMCP = false
    @Published private(set) var conversation: WorkshopCodexThread?
    @Published private(set) var historyMessages: [WorkshopCodexMessage] = []
    @Published private(set) var historyCursor: String?
    @Published private(set) var loadingHistory = false
    @Published private(set) var historyError = ""
    @Published private(set) var activity = ""
    @Published var action: WorkshopTextTransform = .rewrite
    @Published var translationLanguage: WorkshopTranslationLanguage = .automatic
    @Published var instruction = ""
    @Published var budget = 4096
    @Published private(set) var materials: [WorkshopContextMaterial] = []
    @Published private(set) var unavailable = 0
    @Published private(set) var contextEstimate: WorkshopContextPack?
    @Published private(set) var turns: [IslandAITurn] = []
    @Published private(set) var results: [IslandAITextResult] = []
    @Published private(set) var busy = false
    @Published var notice = ""
    @Published var resultID: UUID?
    @Published var showsOriginal = false
    @Published var endpoint: String
    @Published var model: String
    @Published private(set) var taskDefinition: WorkshopTaskDefinition?
    @Published private(set) var taskName = ""
    @Published var taskParameters: [String: String] = [:]
    private var threadID: String?
    private var historyJob: Task<Void, Never>?
    private var historyGeneration = UUID()
    private var job: Task<Void, Never>?
    private var generation = UUID()
    private let file: URL
    private let saveQueue = DispatchQueue(label: "com.cliperx.context-draft", qos: .utility)
    private var saveWork: DispatchWorkItem?
    private var saveGeneration = UUID()
    private var cachedPack: WorkshopContextPack?
    private var cachedBudget = 0
    private var estimateJob: Task<Void, Never>?
    @Published private(set) var composerLayoutHeight: CGFloat = 114
    @Published private(set) var historyLayoutHeight: CGFloat = 28
    private static let maximumHistoryHeight: CGFloat = 420
    @Published private(set) var historyHeightLimit: CGFloat = IslandAISession.maximumHistoryHeight
    private var pendingComposerHeight: CGFloat = 114
    private var pendingHistoryHeight: CGFloat = 28
    private var layoutJob: Task<Void, Never>?
    @Published private(set) var textLayoutHeight = WorkshopTextLayout.minimumResultHeight
    private var pendingTextHeight = WorkshopTextLayout.minimumResultHeight
    private var textCache: [String: String] = [:]
    private var textCacheOrder: [String] = []

    init(id: UUID, mode: IslandAIMode, directory: URL? = nil) {
        self.id = id
        self.mode = mode
        endpoint = UserDefaults.standard.string(forKey: "CliperX.widgetModel.endpoint") ?? "https://api.deepseek.com/chat/completions"
        model = UserDefaults.standard.string(forKey: "CliperX.widgetModel.model") ?? "deepseek-chat"
        if mode == .text { action = .translate; target = "lingjian" }
        let drafts = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.clipnote.app/WidgetWorkshop/drafts", isDirectory: true)
        file = drafts.appendingPathComponent("\(id)-\(mode.rawValue).json")
        if let data = try? Data(contentsOf: file), data.count <= 2_097_152, let saved = try? JSONDecoder().decode(IslandAIDraft.self, from: data) {
            selected = Array(saved.selected.prefix(20))
            question = saved.question
            target = ["lingjian", "codex", "apple", "compatible"].contains(saved.target) ? saved.target : "lingjian"
            action = WorkshopTextTransform(rawValue: saved.action) ?? .rewrite
            instruction = saved.instruction
            budget = [1024, 2048, 4096, 8192].contains(saved.budget) ? saved.budget : 4096
            turns = saved.turns
            results = saved.results
            taskParameters = saved.taskParameters ?? [:]
            threadID = saved.threadID
            conversation = saved.conversation
            if conversation == nil, let threadID {
                conversation = try? WorkshopCodexThread(["id": threadID, "name": "已有 Codex 对话", "modelProvider": "openai"])
            }
            for index in turns.indices where turns[index].phase == .working {
                turns[index].phase = .stopped
                turns[index].error = "上次运行已中断，问题与材料已保留。"
            }
            for index in results.indices where results[index].phase == .working {
                results[index].phase = .stopped
                results[index].error = "上次处理已中断。"
            }
            resultID = results.first?.id
            if mode == .text {
                endpoint = saved.endpoint ?? endpoint
                model = saved.model ?? model
                let legacyLanguage = saved.action == WorkshopTextTransform.translate.rawValue
                    ? WorkshopTranslationLanguage.allCases.first { $0.title == saved.instruction.trimmingCharacters(in: .whitespacesAndNewlines) } : nil
                translationLanguage = WorkshopTranslationLanguage(rawValue: saved.translationLanguage ?? "") ?? legacyLanguage ?? .automatic
                selected = Array(selected.prefix(1))
                if saved.textPreferencesVersion == nil {
                    action = .translate
                    resultID = nil
                } else if saved.textPreferencesVersion == 1 {
                    resultID = results.first { $0.cacheKey != nil }?.id
                } else {
                    resultID = saved.activeTextResultID
                }
                for result in results where result.isComplete {
                    if let key = result.cacheKey { rememberText(result.output, key: key) }
                }
            }
        } else if mode == .context {
            let legacy = UserDefaults.standard.dictionary(forKey: "CliperX.widgetContext.\(id)") ?? [:]
            selected = Array((legacy["selected"] as? [String] ?? []).compactMap(UUID.init(uuidString:)).prefix(20))
            question = String((legacy["task"] as? String ?? "").prefix(4000))
        }
    }
    var conversationTitle: String {
        guard let conversation else { return "新建对话" }
        return conversation.title.isEmpty ? "Codex 对话" : conversation.title
    }
    var hasPanel: Bool { true }
    func configureTask(_ manifest: WorkshopManifest?) {
        let definition = mode == .context ? manifest?.task : nil
        let name = definition == nil ? "" : manifest?.name ?? ""
        guard taskDefinition != definition || taskName != name else { return }
        if busy { stop() }
        taskDefinition = definition
        taskName = name
        taskParameters = Dictionary(uniqueKeysWithValues: (definition?.parameters ?? []).map {
            ($0.key, taskParameters[$0.key] ?? $0.defaultValue)
        })
    }
    var taskValidationMessage: String? {
        guard !busy, let task = taskDefinition else { return nil }
        guard materials.count >= task.input.minItems else { return "请选择至少 \(task.input.minItems) 条材料。" }
        guard materials.count <= task.input.maxItems else { return "这个组件最多接受 \(task.input.maxItems) 条材料。" }
        guard materials.allSatisfy({ task.input.types.contains($0.imageData == nil ? "text" : "image") }) else {
            return "所选材料包含这个组件不支持的类型。"
        }
        do { _ = try task.render(parameters: taskParameters, question: question) }
        catch { return error.localizedDescription }
        return nil
    }
    var hasResults: Bool { mode == .text ? currentResult != nil : conversation != nil || !turns.isEmpty || !historyMessages.isEmpty }
    var feedback: String {
        if unavailable > 0 { return "\(unavailable) 条材料已失效，可从已选材料中移除。" }
        if question.count > 4000 { return "任务最多 4000 字。" }
        if instruction.count > 500 { return "处理要求最多 500 字。" }
        if let taskValidationMessage { return taskValidationMessage }
        return notice
    }
    var visibleContextTurns: [IslandAITurn] { turns.filter { $0.isWorking || !$0.answer.isEmpty || $0.isComplete } }
    var hasConversationContent: Bool { loadingHistory || !historyMessages.isEmpty || !visibleContextTurns.isEmpty }
    var contextFailure: IslandAITurn? {
        guard !busy, let turn = turns.last, !turn.error.isEmpty else { return nil }
        let draft = question.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft.isEmpty || draft == turn.question.trimmingCharacters(in: .whitespacesAndNewlines) ? turn : nil
    }
    var contextFeedback: String {
        if !feedback.isEmpty { return feedback }
        if !historyError.isEmpty { return historyError }
        return contextFailure?.error ?? ""
    }
    var contextHistoryHeight: CGFloat {
        hasConversationContent ? min(max(IslandTaskLayout.minimumAnswerHeight, historyLayoutHeight), historyHeightLimit) : 0
    }
    var minimumPanelHeight: CGFloat {
        IslandTaskLayout.chromeHeight + composerLayoutHeight
            + (hasConversationContent ? IslandTaskLayout.minimumAnswerHeight : 0)
    }
    var naturalPanelHeight: CGFloat {
        guard hasPanel else { return 0 }
        if mode == .context {
            return IslandTaskLayout.chromeHeight + composerLayoutHeight
                + (hasConversationContent ? max(IslandTaskLayout.minimumAnswerHeight, historyLayoutHeight) : 0)
        }
        guard currentResult != nil else { return IslandTaskLayout.chromeHeight + WorkshopTextLayout.readyHeight }
        return IslandTaskLayout.chromeHeight + WorkshopTextLayout.controlsHeight + textLayoutHeight
    }
    var panelHeight: CGFloat {
        guard hasPanel else { return 0 }
        if mode == .context { return IslandTaskLayout.chromeHeight + composerLayoutHeight + contextHistoryHeight }
        guard currentResult != nil else { return IslandTaskLayout.chromeHeight + WorkshopTextLayout.readyHeight }
        return IslandTaskLayout.chromeHeight + WorkshopTextLayout.controlsHeight + min(textLayoutHeight, historyHeightLimit)
    }
    func setContextHeightBudget(_ height: CGFloat) {
        let controlsHeight = mode == .context ? composerLayoutHeight
            : currentResult == nil ? WorkshopTextLayout.readyHeight : WorkshopTextLayout.controlsHeight
        let limit = min(Self.maximumHistoryHeight, max(0, height - IslandTaskLayout.chromeHeight - controlsHeight))
        if historyHeightLimit != limit { historyHeightLimit = limit }
    }
    func updateContextLayout(historyHeight: CGFloat? = nil, composerHeight: CGFloat? = nil) {
        guard mode == .context else { return }
        if let height = historyHeight, height.isFinite {
            pendingHistoryHeight = min(Self.maximumHistoryHeight, max(28, ceil(height / 2) * 2))
        }
        if let height = composerHeight, height.isFinite { pendingComposerHeight = max(64, ceil(height / 2) * 2) }
        scheduleLayoutUpdate()
    }
    func updateTextLayout(height: CGFloat) {
        guard mode == .text, height.isFinite else { return }
        pendingTextHeight = min(Self.maximumHistoryHeight, max(WorkshopTextLayout.minimumResultHeight, ceil(height / 2) * 2))
        scheduleLayoutUpdate()
    }
    private func scheduleLayoutUpdate() {
        guard pendingHistoryHeight != historyLayoutHeight || pendingComposerHeight != composerLayoutHeight || pendingTextHeight != textLayoutHeight,
              layoutJob == nil else { return }
        layoutJob = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self else { return }
            self.layoutJob = nil
            if self.historyLayoutHeight != self.pendingHistoryHeight { self.historyLayoutHeight = self.pendingHistoryHeight }
            if self.composerLayoutHeight != self.pendingComposerHeight { self.composerLayoutHeight = self.pendingComposerHeight }
            if self.textLayoutHeight != self.pendingTextHeight { self.textLayoutHeight = self.pendingTextHeight }
            IslandAIWorkspace.shared.reflow()
        }
    }
    var canSend: Bool {
        !busy && unavailable == 0 && taskValidationMessage == nil && (mode == .context
            ? question.count <= 4000 && (taskDefinition != nil || !materials.isEmpty || !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            : !materials.isEmpty && instruction.count <= 500 && (action != .custom || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    var pack: WorkshopContextPack {
        if let cachedPack, cachedBudget == budget { return cachedPack }
        let value = WorkshopContextComposer.compose(task: "", materials: materials.filter { $0.imageData == nil }, budget: budget, unavailable: unavailable)
        cachedPack = value; cachedBudget = budget
        return value
    }
    var currentResult: IslandAITextResult? { results.first { $0.id == resultID } }

    func refreshMaterials() {
        let current = selected.compactMap { try? ClipboardLibrary.shared.widgetContextMaterial(id: $0, includeImages: mode == .context) }
        let missing = selected.count - current.count
        guard current != materials || missing != unavailable else { return }
        cachedPack = nil
        materials = current
        unavailable = missing
        updateContextEstimate()
    }
    func updateContextEstimate() {
        guard mode == .context else { return }
        estimateJob?.cancel()
        contextEstimate = nil
        let materials = materials, budget = budget, unavailable = unavailable
        estimateJob = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            let value = await Task.detached(priority: .userInitiated) {
                WorkshopContextComposer.compose(task: "", materials: materials.filter { $0.imageData == nil }, budget: budget, unavailable: unavailable)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.cachedPack = value; self.cachedBudget = budget; self.contextEstimate = value
        }
    }
    func toggle(_ material: WorkshopContextMaterial) {
        if mode == .text { selectText(material); return }
        guard mode == .context || material.imageData == nil else { notice = "文本处理仅支持文字素材。"; return }
        cachedPack = nil
        if selected.contains(material.id) {
            selected.removeAll { $0 == material.id }
            materials.removeAll { $0.id == material.id }
        } else if let task = taskDefinition, !task.input.types.contains(material.imageData == nil ? "text" : "image") {
            notice = "这个组件不接受\(material.imageData == nil ? "文字" : "图片")材料。"; changed(); return
        } else if selected.count < (taskDefinition?.input.maxItems ?? 20) {
            selected.append(material.id)
            materials.append(material)
        } else { notice = "最多选择 \(taskDefinition?.input.maxItems ?? 20) 条素材。"; changed(); return }
        notice = ""
        unavailable = selected.count - materials.count
        updateContextEstimate()
        changed()
    }
    func remove(_ id: UUID) { cachedPack = nil; selected.removeAll { $0 == id }; materials.removeAll { $0.id == id }; unavailable = selected.count - materials.count; updateContextEstimate(); changed() }
    func clearSelection() { cachedPack = nil; selected = []; materials = []; unavailable = 0; notice = ""; updateContextEstimate(); changed() }
    private var draft: IslandAIDraft {
        IslandAIDraft(selected: selected, question: question, target: target, action: action.rawValue,
                      instruction: instruction, budget: budget, turns: Array(turns.suffix(6)), results: results,
                      threadID: threadID, conversation: conversation, translationLanguage: translationLanguage.rawValue,
                      textPreferencesVersion: mode == .text ? 2 : nil,
                      endpoint: mode == .text ? endpoint : nil, model: mode == .text ? model : nil,
                      activeTextResultID: mode == .text ? resultID : nil,
                      taskParameters: taskParameters.isEmpty ? nil : taskParameters)
    }
    private nonisolated static func write(_ draft: IslandAIDraft, to file: URL) throws {
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 2_097_152 else { throw WorkshopError.invalid("草稿过大。") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    func changed() {
        saveWork?.cancel()
        let draft = draft, file = file, token = UUID()
        saveGeneration = token
        let work = DispatchWorkItem { [weak self] in
            do { try Self.write(draft, to: file) }
            catch {
                Task { @MainActor in
                    guard let self, self.saveGeneration == token else { return }
                    self.notice = "草稿保存失败，当前内容仍在内存中。"
                    IslandAIWorkspace.shared.reflow()
                }
            }
        }
        saveWork = work
        saveQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
        IslandAIWorkspace.shared.reflow()
    }
    func flushDraft() {
        saveGeneration = UUID()
        saveWork?.cancel()
        let draft = draft, file = file
        do { try saveQueue.sync { try Self.write(draft, to: file) } }
        catch { notice = "草稿保存失败，当前内容仍在内存中。" }
    }
    func saveModel() {
        UserDefaults.standard.set(endpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "CliperX.widgetModel.endpoint")
        UserDefaults.standard.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "CliperX.widgetModel.model")
        changed()
    }
    func targetChanged() { threadID = nil; changed() }
    func newConversation() {
        guard !busy else { return }
        historyJob?.cancel(); historyGeneration = UUID()
        turns = []; historyMessages = []; historyCursor = nil; historyError = ""; loadingHistory = false
        historyLayoutHeight = 28; pendingHistoryHeight = 28
        conversation = nil; threadID = nil; notice = ""; changed()
    }
    func selectConversation(_ thread: WorkshopCodexThread) {
        guard !busy, !thread.busy else { return }
        newConversation()
        conversation = thread; threadID = thread.id
        IslandWorkspaceState.shared.clipboardExpanded = false
        loadHistory()
        changed()
    }
    func loadHistory(older: Bool = false) {
        guard !busy, !loadingHistory, let conversation else { return }
        let cursor = older ? historyCursor : nil
        guard !older || cursor != nil else { return }
        loadingHistory = true; historyError = ""
        let token = UUID(); historyGeneration = token
        historyJob = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.historyGeneration == token { self.loadingHistory = false; self.historyJob = nil; IslandAIWorkspace.shared.reflow() } }
            do {
                let page = try await WorkshopCodexConversation().history(threadID: conversation.id, cursor: cursor)
                try Task.checkCancellation()
                guard self.historyGeneration == token else { return }
                if older {
                    let ids = Set(self.historyMessages.map(\.id))
                    self.historyMessages = page.messages.filter { !ids.contains($0.id) } + self.historyMessages
                } else {
                    // Preserve interrupted local questions until the user explicitly
                    // retries or switches conversations.
                    let incomplete = self.turns.filter { !$0.isComplete }
                    self.historyMessages = page.messages; self.turns = incomplete
                }
                self.historyCursor = page.nextCursor
            } catch {
                guard self.historyGeneration == token else { return }
                self.historyError = String(error.localizedDescription.prefix(300))
            }
        }
    }
    func stop() {
        generation = UUID()
        job?.cancel(); job = nil; busy = false; activity = "已停止"
        for index in turns.indices where turns[index].phase == .working { turns[index].phase = .stopped; turns[index].error = "已停止，可重新发送。" }
        for index in results.indices where results[index].phase == .working { results[index].phase = .stopped; results[index].error = "已停止。" }
        changed()
    }
    private var requestIsSensitive: Bool {
        ClipboardAIPrivacy.isSensitive(question) || ClipboardAIPrivacy.isSensitive(instruction)
            || taskParameters.values.contains(where: ClipboardAIPrivacy.isSensitive)
    }
    func send() {
        refreshMaterials()
        guard canSend else { notice = unavailable > 0 ? "部分素材已失效，请从已选材料中移除后重试。" : "请检查文字与选择。"; changed(); return }
        guard !requestIsSensitive else {
            notice = "问题或处理要求触发了隐私过滤，请调整后重试。"; changed(); return
        }
        if mode == .context { sendContext() }
        else if let material = materials.first { selectText(material, force: true) }
    }
    private func configuration() -> WorkshopModelConfiguration {
        let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(provider: target, endpoint: address, model: model.trimmingCharacters(in: .whitespacesAndNewlines), secret: target == "compatible" ? WorkshopModelKeychain.load(address) : "")
    }
    private func sendContext(questionOverride: String? = nil) {
        let originalQuestion = question
        let question: String
        do { question = try questionOverride ?? taskDefinition?.render(parameters: taskParameters, question: originalQuestion) ?? originalQuestion }
        catch { notice = error.localizedDescription; changed(); return }
        let materials = materials, budget = budget, useMCP = useMCP, conversation = conversation
        let earlierSources = (turns.reversed().map(\.answerSources) + historyMessages.reversed().map(\.sources))
            .reduce([]) { WorkshopConversationContext.merging($0, $1) }
        let token = UUID(); generation = token
        let turn = IslandAITurn(id: UUID(), question: originalQuestion.isEmpty ? (taskName.isEmpty ? "概括所选材料" : taskName) : originalQuestion,
                                attachments: materials.map { IslandAIAttachment(id: $0.id, title: $0.title, source: $0.source, isImage: $0.imageData != nil) },
                                taskQuestion: taskDefinition == nil ? nil : question)
        historyJob?.cancel(); historyGeneration = UUID(); loadingHistory = false
        IslandWorkspaceState.shared.clipboardExpanded = false
        busy = true; notice = ""; activity = "正在连接 Codex…"; turns.append(turn)
        self.question = ""; selected = []; self.materials = []; cachedPack = nil; updateContextEstimate(); changed()
        job = Task { @MainActor [weak self] in
            guard let self else { return }
            let access = WorkshopContextAccess()
            defer {
                access.close()
                if self.generation == token { self.busy = false; self.job = nil; self.activity = ""; self.changed() }
            }
            do {
                let mcp = useMCP ? try await access.open() : nil
                let input = try await Task.detached(priority: .userInitiated) {
                    try WorkshopContextInput.make(question: question, materials: materials, budget: budget, useMCP: useMCP)
                }.value
                try Task.checkCancellation()
                if let text = input.first?["text"] as? String, let context = WorkshopConversationContext.decode(text),
                   let index = self.turns.firstIndex(where: { $0.id == turn.id }) {
                    self.turns[index].sources = WorkshopConversationContext.merging(context.sources, earlierSources)
                }
                let reply = try await WorkshopCodexConversation().answer(thread: conversation, input: input, mcp: mcp, onThread: { thread in
                    guard self.generation == token else { return }
                    self.conversation = thread; self.threadID = thread.id; self.changed()
                }, onUpdate: { answer, status in
                    guard self.generation == token, let index = self.turns.firstIndex(where: { $0.id == turn.id }) else { return }
                    self.activity = status
                    if !answer.isEmpty { self.turns[index].answer = answer }
                }, onSources: { sources in
                    guard self.generation == token, let index = self.turns.firstIndex(where: { $0.id == turn.id }) else { return }
                    self.turns[index].sources = WorkshopConversationContext.merging(self.turns[index].answerSources, sources)
                })
                try Task.checkCancellation()
                guard self.generation == token, let index = self.turns.firstIndex(where: { $0.id == turn.id }) else { return }
                self.turns[index].answer = reply.text; self.turns[index].phase = .complete
            } catch {
                guard self.generation == token, let index = self.turns.firstIndex(where: { $0.id == turn.id }) else { return }
                self.turns[index].error = String(error.localizedDescription.prefix(500)); self.turns[index].phase = .failed
                if self.question.isEmpty { self.question = originalQuestion }
                if self.selected.isEmpty { self.selected = materials.map(\.id); self.refreshMaterials() }
            }
        }
    }
    func retryContext(_ turn: IslandAITurn) {
        guard !busy else { return }
        question = turn.question
        selected = turn.attachments.map(\.id)
        refreshMaterials()
        guard canSend else { notice = feedback; changed(); return }
        guard !requestIsSensitive else {
            notice = "问题或处理要求触发了隐私过滤，请调整后重试。"; changed(); return
        }
        sendContext(questionOverride: turn.taskQuestion)
    }
    func retryResult() {
        guard let id = selected.first, let material = try? ClipboardLibrary.shared.widgetContextMaterial(id: id) else {
            notice = "原文已删除或当前无法读取。"; changed(); return
        }
        selectText(material, force: true)
    }
    func textPreferencesChanged() {
        guard mode == .text else { return }
        saveModel()
        if let id = selected.first, let material = try? ClipboardLibrary.shared.widgetContextMaterial(id: id) {
            selectText(material)
        } else {
            stop()
            resultID = nil
            if !selected.isEmpty { notice = "原文已删除或当前无法读取。" }
            changed()
        }
    }

    func selectText(_ material: WorkshopContextMaterial, force: Bool = false) {
        guard mode == .text else { return }
        do {
            let original = try ClipboardLibrary.shared.widgetContextMaterial(id: material.id)
            guard !original.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  original.content.count <= 6000 else { throw WorkshopError.invalid("请选择 6000 字以内的文字卡片。") }
            guard instruction.count <= 500, !ClipboardAIPrivacy.isSensitive(instruction) else {
                throw WorkshopError.invalid("处理要求过长或触发了隐私过滤，请调整后重试。")
            }
            guard action != .custom || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkshopError.invalid("请在组件设置中填写处理要求。")
            }
            let configuration = configuration()
            let request = try WorkshopTextRequest(input: original.content, action: action, language: translationLanguage,
                                                  instruction: instruction, provider: target, endpoint: configuration.endpoint,
                                                  model: configuration.model, secret: configuration.secret)
            if !force, busy, currentResult?.cacheKey == request.cacheKey { return }
            generation = UUID()
            let token = generation
            job?.cancel()
            job = nil
            busy = false
            activity = ""
            selected = [original.id]
            materials = [original]
            unavailable = 0
            showsOriginal = false
            if resultID != original.id {
                textLayoutHeight = WorkshopTextLayout.minimumResultHeight
                pendingTextHeight = WorkshopTextLayout.minimumResultHeight
            }
            resultID = original.id
            notice = ""
            var result = IslandAITextResult(id: original.id, title: original.title, original: original.content)
            result.cacheKey = request.cacheKey
            if !force, let cached = textCache[request.cacheKey] {
                result.output = cached
                result.phase = .complete
                results = [result]
                rememberText(cached, key: request.cacheKey)
                changed()
                return
            }
            results = [result]
            busy = true
            activity = "正在\(action.title)…"
            changed()
            job = Task { @MainActor [weak self] in
                guard let self else { return }
                defer {
                    if self.generation == token { self.busy = false; self.job = nil; self.activity = ""; self.changed() }
                }
                do {
                    try Task.checkCancellation()
                    let output = try await configuration.generate(action: request.action, input: request.input, instruction: request.instruction) { [weak self] output in
                        guard let self, self.generation == token, self.results.first?.isWorking == true else { return }
                        self.results[0].output = String(output.prefix(20000))
                    }
                    try Task.checkCancellation()
                    guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, output.count <= 20000 else {
                        throw WorkshopError.invalid("处理结果为空或超过 20000 字，请缩短原文后重试。")
                    }
                    guard self.generation == token else { return }
                    self.results[0].output = output
                    self.results[0].phase = .complete
                    self.rememberText(output, key: request.cacheKey)
                } catch {
                    guard self.generation == token else { return }
                    self.results[0].error = String(error.localizedDescription.prefix(400))
                    self.results[0].phase = .failed
                }
            }
        } catch {
            stop()
            resultID = nil
            notice = String(error.localizedDescription.prefix(400))
            changed()
        }
    }

    private func rememberText(_ output: String, key: String) {
        textCache[key] = output
        textCacheOrder.removeAll { $0 == key }
        textCacheOrder.append(key)
        if textCacheOrder.count > 20 { textCache.removeValue(forKey: textCacheOrder.removeFirst()) }
    }
    func copyResult() {
        guard let text = currentResult?.output, !text.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        notice = ""
        ClipboardMonitor.shared.showToast("已复制结果")
    }
    func saveResult() {
        guard let text = currentResult?.output, !text.isEmpty else { return }
        do { try ClipboardLibrary.shared.createItem(content: text); notice = "已保存为新片段" }
        catch { notice = error.localizedDescription }
    }
}

@MainActor
final class IslandAIWorkspace: ObservableObject {
    static let shared = IslandAIWorkspace()
    @Published private(set) var active: IslandAISession?
    @Published private(set) var selection: IslandAISession?
    @Published private(set) var isCollapsed = false
    @Published private(set) var revision = 0
    @Published private(set) var citationReveal: WorkshopCitationReveal?
    private var sessions: [String: IslandAISession] = [:]
    private let draftDirectory: URL?
    private var layoutSignature = ""
    private var presentedPopover: (id: UUID, dismiss: () -> Void)?
    private var selectionObserver: AnyCancellable?
    init(draftDirectory: URL? = nil) { self.draftDirectory = draftDirectory }
    var isActive: Bool { active != nil && !isCollapsed }
    var extraHeight: CGFloat {
        guard let active else { return 0 }
        return isCollapsed ? IslandTaskLayout.chromeHeight : active.panelHeight
    }
    func session(id: UUID, mode: IslandAIMode) -> IslandAISession {
        let key = "\(id)-\(mode.rawValue)"
        let session = sessions[key] ?? IslandAISession(id: id, mode: mode, directory: draftDirectory)
        let instance = IslandWidgetPreferences.shared.configuration.widgets.first { $0.id == id }
        session.configureTask(instance.flatMap { WidgetWorkshopStore.shared.manifest($0.kind.pluginID) })
        sessions[key] = session
        return session
    }
    func deactivate(pluginID: String) {
        let ids = Set(IslandWidgetPreferences.shared.configuration.widgets.filter { $0.kind.pluginID == pluginID }.map(\.id))
        for session in sessions.values where ids.contains(session.id) { session.stop() }
        if let active, ids.contains(active.id) { exit() }
    }
    func removeInstance(_ id: UUID) {
        for (key, session) in sessions where session.id == id {
            session.stop()
            session.flushDraft()
            sessions.removeValue(forKey: key)
        }
        if active?.id == id { exit() }
    }
    func busy(id: UUID) -> Bool { sessions.values.contains { $0.id == id && $0.busy } }
    func selectMaterials(for session: IslandAISession?) {
        selectionObserver = nil
        selection = session
        selectionObserver = session?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func toggle(id: UUID, mode: IslandAIMode) {
        IslandAgentWorkspace.shared.hide()
        if active?.id == id, active?.mode == mode {
            if isCollapsed { expand() }
            return
        }
        dismissPresentedPopover()
        PasteQueueService.shared.closePanel()
        active?.changed()
        let session = session(id: id, mode: mode)
        session.refreshMaterials()
        selectMaterials(for: session)
        withAnimation(.easeOut(duration: 0.22)) {
            active = session
            isCollapsed = false
        }
        if mode == .text { IslandWorkspaceState.shared.clipboardExpanded = false }
        IslandWorkspaceState.shared.show(.clipboard)
        reflow()
    }
    func collapse() {
        guard active != nil, !isCollapsed else { return }
        dismissPresentedPopover()
        active?.changed()
        selectMaterials(for: nil)
        withAnimation(.easeOut(duration: 0.25)) { isCollapsed = true }
        reflow()
    }
    func expand() {
        guard active != nil, isCollapsed else { return }
        selectMaterials(for: active)
        withAnimation(.easeOut(duration: 0.28)) { isCollapsed = false }
        reflow()
    }
    func presentPopover(id: UUID, dismiss: @escaping () -> Void) { presentedPopover = (id, dismiss) }
    @discardableResult
    func revealCitation(_ source: WorkshopContextSource) -> Bool {
        guard let itemID = source.clipboardID else { return false }
        dismissPresentedPopover()
        citationReveal = WorkshopCitationReveal(itemID: itemID, label: source.label)
        return true
    }
    func clearPopover(id: UUID) { if presentedPopover?.id == id { presentedPopover = nil } }
    @discardableResult func dismissPresentedPopover() -> Bool {
        guard let popover = presentedPopover else { return false }
        presentedPopover = nil; popover.dismiss(); return true
    }
    func exit() {
        dismissPresentedPopover()
        active?.changed()
        selectMaterials(for: nil)
        withAnimation(.easeOut(duration: 0.22)) {
            active = nil
            isCollapsed = false
        }
        reflow()
    }
    func flushDrafts() { for session in sessions.values { session.flushDraft() } }
    func reflow() {
        let screen = AppDelegate.shared?.panel?.screen ?? ScreenHelper.targetScreen()
        let availableHeight = IslandPanelLimits.heightLimit(
            screenHeight: screen?.frame.height ?? 1000,
            panelMaximumHeight: AppDelegate.shared?.panel?.maxSize.height ?? IslandPanelLimits.maximumHeight)
        let width = AppDelegate.shared?.panel?.frame.width ?? CGFloat(SettingsManager.shared.islandPanelWidth)
        if let active, !isCollapsed, IslandWorkspaceState.shared.page == .clipboard {
            let allocation = IslandWorkspaceState.shared.layout(width: width, heightLimit: availableHeight)
            active.setContextHeightBudget(allocation.taskOuter?.height ?? 0)
        }
        let busySessions = sessions.values.filter(\.busy).map { $0.id.uuidString }.sorted()
        let signature = "\(active?.id.uuidString ?? "")-\(active?.mode.rawValue ?? "")-\(isCollapsed)-\(active?.selected ?? [])-\(active?.action.rawValue ?? "")-\(busySessions)-\(extraHeight)"
        if signature != layoutSignature { layoutSignature = signature; revision += 1 }
        let monitor = ClipboardMonitor.shared
        let blocksCollapse = isActive || IslandAgentWorkspace.shared.isOpen || PasteQueueService.shared.isOpen
            || IslandWorkspaceState.shared.writingPresented || IslandWorkspaceState.shared.page != .clipboard
        if monitor.blockAutoCollapse != blocksCollapse { monitor.blockAutoCollapse = blocksCollapse }
        if monitor.clipboardWritingActive != blocksCollapse { monitor.clipboardWritingActive = blocksCollapse }
        let height = IslandWorkspaceState.shared.layout(width: width, heightLimit: availableHeight).panelSize.height
        if abs(SettingsManager.shared.islandPanelHeight - Double(height)) > 0.5 {
            AppDelegate.shared?.resizeIslandWorkspace()
        }
    }
}
