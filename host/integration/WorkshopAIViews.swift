import AppKit
import SwiftUI

struct IslandAIWorkbench: View {
    @ObservedObject var session: IslandAISession
    var allocatedHeight: CGFloat? = nil
    @ObservedObject private var ai = IslandAIWorkspace.shared
    @State private var threadsPopoverID = UUID()
    @State private var showsThreads = false

    private var taskHeight: CGFloat { allocatedHeight ?? ai.extraHeight }
    private var bodyHeight: CGFloat { max(0, taskHeight - IslandTaskLayout.chromeHeight) }

    private var composerViewportHeight: CGFloat {
        let answerMinimum = session.hasConversationContent ? min(IslandTaskLayout.minimumAnswerHeight, bodyHeight * 0.45) : 0
        return min(session.composerLayoutHeight, max(0, bodyHeight - answerMinimum))
    }

    var body: some View {
        IslandTaskSurface(height: taskHeight, isCollapsed: ai.isCollapsed) {
            taskHeader
        } content: {
            if session.mode == .context {
                contextQuestionAnswer
            } else {
                WorkshopTextWorkbench(session: session, heightLimit: bodyHeight)
            }
        } footer: {
            if session.mode == .context {
                ScrollView {
                    contextComposer
                }
                .scrollIndicators(.never)
                .frame(height: composerViewportHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: session.instruction) { _, _ in session.changed() }
    }

    private var taskHeader: some View {
        HStack(spacing: IslandLayoutSpacing.actionGap) {
            Text(session.taskName.isEmpty ? (session.mode == .context ? "上下文" : "翻译") : session.taskName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Rectangle().fill(.primary.opacity(0.09)).frame(width: 1, height: 12)
                .accessibilityHidden(true)
            if session.mode == .context {
                conversationSelector
            } else if session.action == .translate {
                Menu {
                    Picker("目标语言", selection: $session.translationLanguage) {
                        ForEach(WorkshopTranslationLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(session.translationLanguage.title)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
                    }
                    .font(.system(size: 12))
                    .lineLimit(1)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("翻译目标语言")
            } else {
                Text(session.action.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if ai.isCollapsed { ai.expand() } else { ai.collapse() }
            } label: {
                Image(systemName: ai.isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: IslandLayoutSpacing.iconButtonSize, height: IslandLayoutSpacing.iconButtonSize)
            }
            .buttonStyle(IslandControlStyle(role: .icon)).foregroundStyle(.secondary)
            .accessibilityLabel(ai.isCollapsed ? "展开任务" : "收起任务")
            Button {
                ai.exit()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
                    .frame(width: IslandLayoutSpacing.iconButtonSize, height: IslandLayoutSpacing.iconButtonSize)
            }
            .buttonStyle(IslandControlStyle(role: .icon)).foregroundStyle(.secondary)
            .accessibilityLabel("关闭任务")
        }
    }

    private var contextQuestionAnswer: some View {
        Group {
            if session.hasConversationContent {
                conversationHistory
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { if session.conversation != nil && session.historyMessages.isEmpty { session.loadHistory() } }
    }

    private var contextComposer: some View {
        WorkshopContextComposerView(session: session, busy: session.busy, canSend: session.canSend,
                                    onSend: session.send, onStop: session.stop)
    }

    private var conversationSelector: some View {
        Button { showsThreads.toggle() } label: {
            HStack(spacing: 5) {
                Text(session.conversationTitle).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
            }.font(.system(size: 12)).foregroundStyle(.primary)
                .frame(maxWidth: 220, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(IslandControlStyle()).disabled(session.busy)
        .accessibilityLabel("选择 Codex 新建或历史对话")
        .popover(isPresented: $showsThreads, arrowEdge: .top) {
            WorkshopCodexThreadPicker(session: session) { showsThreads = false }
                .onAppear { IslandAIWorkspace.shared.presentPopover(id: threadsPopoverID) { showsThreads = false } }
                .onDisappear { IslandAIWorkspace.shared.clearPopover(id: threadsPopoverID) }
        }
    }

    private var conversationHistory: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.historyCursor != nil {
                        Button("更早的消息") { session.loadHistory(older: true) }
                            .font(.system(size: 10)).foregroundStyle(.secondary).buttonStyle(IslandControlStyle()).disabled(session.loadingHistory)
                    }
                    if session.loadingHistory { ProgressView().controlSize(.mini).frame(height: 22) }
                    ForEach(session.historyMessages) { message in
                        WorkshopConversationMessage(role: message.role, text: message.text, images: message.images,
                                                    context: message.context, sources: message.sources,
                                                    showsCopyButton: session.visibleContextTurns.isEmpty
                                                        && message.id == session.historyMessages.last(where: { $0.role == "assistant" })?.id)
                    }
                    ForEach(session.visibleContextTurns) { turn in
                        VStack(alignment: .leading, spacing: 10) {
                            WorkshopConversationMessage(role: "user", text: turn.question, images: turn.attachments.filter { $0.isImage == true }.count, context: turn.attachmentContext)
                            if !turn.answer.isEmpty {
                                WorkshopConversationMessage(role: "assistant", text: turn.answer, images: 0,
                                                            sources: turn.answerSources,
                                                            showsCopyButton: turn.id == session.visibleContextTurns.last?.id && !turn.isWorking)
                            }
                            if turn.isWorking && turn.answer.isEmpty {
                                HStack(spacing: 7) { ProgressView().controlSize(.mini); Text(session.activity).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("context-answer-bottom")
                }
                .padding(.horizontal, IslandTaskLayout.contentInset).padding(.top, 14).padding(.bottom, 4)
                .background {
                    GeometryReader { geometry in Color.clear.preference(key: WorkshopHistoryHeightKey.self, value: geometry.size.height) }
                }
            }
            .scrollIndicators(.never)
            .onPreferenceChange(WorkshopHistoryHeightKey.self) { session.updateContextLayout(historyHeight: $0) }
            .onAppear { reader.scrollTo("context-answer-bottom", anchor: .bottom) }
            .onChange(of: session.turns.last?.answer) { _, _ in reader.scrollTo("context-answer-bottom", anchor: .bottom) }
            .onChange(of: session.turns.count) { _, _ in reader.scrollTo("context-answer-bottom", anchor: .bottom) }
            .onChange(of: session.historyMessages.isEmpty) { _, empty in if !empty { reader.scrollTo("context-answer-bottom", anchor: .bottom) } }
        }
    }

}

struct WorkshopContextComposerView: View {
    @ObservedObject var session: IslandAISession
    let busy: Bool
    let canSend: Bool
    let onSend: () -> Void
    var onStop: (() -> Void)? = nil
    @ObservedObject private var preferences = IslandWidgetPreferences.shared
    @State private var showsMaterials = false
    @State private var materialsPopoverID = UUID()
    @State private var expandedMaterials = Set<UUID>()
    @State private var previewMaterialID: UUID?
    @State private var previewPopoverID = UUID()
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let task = session.taskDefinition {
                taskControls(task)
            }
            if !session.selected.isEmpty {
                contextAttachments
            }
            TextField(session.taskDefinition == nil ? "询问 Codex…" : "补充要求（可选）…", text: $session.question, axis: .vertical)
                .font(.system(size: 14)).textFieldStyle(.plain).focused($inputFocused)
                .lineLimit(1...3).frame(minHeight: 22, alignment: .topLeading)
                .accessibilityLabel("Codex 问题输入")
            HStack(spacing: 12) {
                Toggle("灵剪 MCP", isOn: $session.useMCP)
                    .toggleStyle(.switch).controlSize(.mini).fixedSize()
                    .font(.system(size: 10)).foregroundStyle(.secondary).disabled(busy)
                    .accessibilityLabel("本次问答使用灵剪 MCP")
                    .help("允许 Codex 只读搜索和读取灵剪历史，所选文字和图片随问题发送。")
                Spacer(minLength: 0)
                if busy {
                    if let onStop {
                        Button(action: onStop) { Image(systemName: "stop.fill").font(.system(size: 11, weight: .semibold)) }
                            .buttonStyle(IslandControlStyle(role: .primary, iconOnly: true)).accessibilityLabel("停止 Codex 回答")
                    } else {
                        ProgressView().controlSize(.mini).frame(width: 28, height: 28)
                    }
                } else {
                    Button(action: onSend) { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)) }
                        .buttonStyle(IslandControlStyle(role: .primary, iconOnly: true))
                        .keyboardShortcut(.return, modifiers: .command).disabled(!canSend)
                        .accessibilityLabel("发送问题并在岛内查看 Codex 回答").help("发送 · ⌘↵")
                }
            }.frame(height: IslandLayoutSpacing.rowButtonSize)
            if !session.contextFeedback.isEmpty { contextFeedback }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(preferences.skin.clipSurface.opacity(inputFocused ? 1 : 0.55),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(inputFocused ? preferences.skin.accent.opacity(0.45) : Color.primary.opacity(0.065), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, IslandTaskLayout.contentInset).padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in Color.clear.preference(key: WorkshopComposerHeightKey.self, value: geometry.size.height) }
        }
        .onPreferenceChange(WorkshopComposerHeightKey.self) { session.updateContextLayout(composerHeight: $0) }
        .onChange(of: session.question) { _, _ in session.changed() }
        .onChange(of: session.taskParameters) { _, _ in session.changed() }
        .onChange(of: session.budget) { _, _ in session.updateContextEstimate(); session.changed() }
        .onChange(of: session.selected) { _, ids in
            if ids.isEmpty { showsMaterials = false }
            if let previewMaterialID, !ids.contains(previewMaterialID) { self.previewMaterialID = nil }
        }
    }

    private func taskControls(_ task: WorkshopTaskDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(task.parameters, id: \.key) { parameter in
                VStack(alignment: .leading, spacing: 3) {
                    Text(parameter.title + (parameter.required == true ? " · 必填" : ""))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    TextField(parameter.title, text: Binding(
                        get: { session.taskParameters[parameter.key] ?? parameter.defaultValue },
                        set: { session.taskParameters[parameter.key] = $0 }
                    ))
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(6).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5))
                    .disabled(busy)
                }
            }
            DisclosureGroup("任务指令与输入要求") {
                VStack(alignment: .leading, spacing: 5) {
                    Text("选择 \(task.input.minItems)～\(task.input.maxItems) 条\(task.input.types.map { $0 == "image" ? "图片" : "文字" }.joined(separator: "、"))材料")
                        .foregroundStyle(.secondary)
                    Text(task.prompt).textSelection(.enabled)
                }
                .font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }

    private var contextAttachments: some View {
        HStack(spacing: 6) {
            ForEach(Array(session.selected.prefix(2)), id: \.self) { id in attachmentChip(id) }
            if session.selected.count > 2 {
                Button { expandedMaterials = []; showsMaterials = true } label: {
                    Text("+\(session.selected.count - 2)").font(.system(size: 10.5)).monospacedDigit()
                        .padding(.horizontal, 8).frame(height: 27)
                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(IslandControlStyle()).accessibilityLabel("查看全部 \(session.selected.count) 项材料")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 27)
        .contextMenu {
            Button("管理材料") { expandedMaterials = []; showsMaterials = true }
            Button("清空材料") { session.clearSelection() }
        }
        .help("点击预览，右键管理材料")
        .popover(isPresented: $showsMaterials) { materialsPopover }
        .popover(isPresented: Binding(get: { previewMaterialID != nil }, set: { if !$0 { previewMaterialID = nil } })) {
            contextAttachmentPreview
                .onAppear { IslandAIWorkspace.shared.presentPopover(id: previewPopoverID) { previewMaterialID = nil } }
                .onDisappear { IslandAIWorkspace.shared.clearPopover(id: previewPopoverID) }
        }
    }

    private func attachmentChip(_ id: UUID) -> some View {
        let material = session.materials.first { $0.id == id }
        return HStack(spacing: 2) {
            Button { previewMaterialID = id } label: {
                HStack(spacing: 5) {
                    if let data = material?.imageData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 21, height: 21)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: material == nil ? "exclamationmark.circle" : "doc.text").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Text(material?.title ?? "材料已失效").font(.system(size: 10.5)).lineLimit(1).frame(maxWidth: 150).fixedSize(horizontal: true, vertical: false)
                }.padding(.leading, 6).frame(height: 27)
            }.buttonStyle(IslandControlStyle(role: .inline)).accessibilityLabel("预览 \(material?.title ?? "已失效材料")")
            Button { revealMaterial(id) } label: {
                Image(systemName: "scope").font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 24, height: 27)
            }
            .buttonStyle(IslandControlStyle(role: .inline)).disabled(material == nil)
            .help("定位上方卡片").accessibilityLabel("定位材料 \(material?.title ?? "已失效材料")")
            Button { session.remove(id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).frame(width: 24, height: 27)
            }.buttonStyle(IslandControlStyle(role: .inline)).accessibilityLabel("移除 \(material?.title ?? "已失效材料")")
        }.background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    private func revealMaterial(_ id: UUID) {
        guard let material = session.materials.first(where: { $0.id == id }) else { return }
        let source = WorkshopContextSource(clipboardID: id, label: "", title: material.title,
                                          source: material.source, isImage: material.imageData != nil)
        IslandAIWorkspace.shared.revealCitation(source)
    }

    @ViewBuilder private var contextAttachmentPreview: some View {
        if let id = previewMaterialID, let material = session.materials.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(material.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                if let data = material.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 300)
                } else {
                    IslandBoundedScroll(maximumHeight: 260) {
                        Text(String(material.content.prefix(12000))).font(.system(size: 12)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text(material.source).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(12).frame(width: 350).foregroundStyle(.primary)
                .background(preferences.skin.taskSurface)
                .environment(\.colorScheme, preferences.skin.scheme)
        } else {
            Text("材料已失效，可移除后重新选择。")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(16).frame(width: 250)
        }
    }

    private var contextFeedback: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(session.contextFeedback).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2).help(session.contextFeedback)
            if let failure = session.contextFailure {
                Button("重试") { session.retryContext(failure) }.font(.system(size: 10.5)).buttonStyle(IslandControlStyle()).disabled(session.busy)
            } else if !session.historyError.isEmpty {
                Button("重试") { session.loadHistory() }.font(.system(size: 10.5)).buttonStyle(IslandControlStyle()).disabled(session.loadingHistory)
            }
            Spacer(minLength: 0)
        }
    }

    private var materialsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已选材料").font(.system(size: 12, weight: .medium))
                Spacer()
                Button("清空") { session.clearSelection() }.buttonStyle(IslandControlStyle())
            }
            IslandBoundedScroll(maximumHeight: 230) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.selected, id: \.self) { id in
                        let material = session.materials.first { $0.id == id }
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top) {
                                Button {
                                    if expandedMaterials.contains(id) { expandedMaterials.remove(id) }
                                    else { expandedMaterials.insert(id) }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(material?.title ?? "素材已失效").lineLimit(2)
                                        Text(material?.source ?? "请移除此项后重试").font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(IslandControlStyle())
                                Button { revealMaterial(id) } label: { Image(systemName: "scope") }
                                    .buttonStyle(IslandControlStyle(role: .inline)).disabled(material == nil)
                                    .help("定位上方卡片").accessibilityLabel("定位材料")
                                Button { session.remove(id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(IslandControlStyle(role: .inline)).accessibilityLabel("移除材料")
                            }
                            if expandedMaterials.contains(id), let material {
                                if let data = material.imageData, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 190)
                                } else { Text(String(material.content.prefix(6000))).font(.system(size: 11)).textSelection(.enabled) }
                                if material.imageData == nil && material.content.count > 6000 { Text("预览前 6000 字").font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }.font(.system(size: 11))
            }
            if session.mode == .context {
                Text("文字约 \(session.pack.estimatedTokens) tokens · \(session.materials.filter { $0.imageData != nil }.count) 张图片 · \(session.pack.shortened) 条受预算裁剪")
                    .font(.caption2).foregroundStyle(.secondary)
                Picker("文字预算", selection: $session.budget) {
                    ForEach([1024, 2048, 4096, 8192], id: \.self) { Text("约 \($0) tokens").tag($0) }
                }
            }
        }.padding(12).frame(width: 320).foregroundStyle(.primary)
            .background(preferences.skin.taskSurface)
            .environment(\.colorScheme, preferences.skin.scheme)
            .onAppear { IslandAIWorkspace.shared.presentPopover(id: materialsPopoverID) { showsMaterials = false } }
            .onDisappear { IslandAIWorkspace.shared.clearPopover(id: materialsPopoverID) }
    }
}

private struct WorkshopComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
private struct WorkshopHistoryHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct WorkshopConversationMessage: View {
    let role: String
    let text: String
    let images: Int
    var context: WorkshopConversationContext? = nil
    var sources: [WorkshopContextSource] = []
    var showsCopyButton = false
    @State private var showsSources = false
    @State private var sourcesPopoverID = UUID()
    @State private var hovered = false
    @State private var expanded = false
    @FocusState private var copyFocused: Bool

    var body: some View {
        VStack(alignment: role == "user" ? .trailing : .leading, spacing: 5) {
            if role == "user" {
                HStack {
                    Spacer(minLength: 40)
                    Text(text).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.78))
                        .lineLimit(expanded ? nil : 3).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                        .contextMenu {
                            Button(expanded ? "收起问题" : "展开问题") { expanded.toggle() }
                            Button("复制问题") { copy() }
                        }
                }
            } else {
                WorkshopAnswerView(text: text, sources: sources, fontSize: 14.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu { Button("复制回答") { copy() } }
                HStack {
                    Spacer(minLength: 0)
                    IslandCopyButton(text: text, title: "复制回答")
                        .focused($copyFocused)
                        .opacity(showsCopyButton || hovered || copyFocused ? 1 : 0)
                }
            }
            if let context, !context.sources.isEmpty {
                Button { showsSources.toggle() } label: {
                    Label("\(context.sources.count) 项材料", systemImage: "paperclip").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(IslandControlStyle()).help(context.summary).accessibilityLabel("\(context.sources.count) 项材料，\(context.summary)")
                    .popover(isPresented: $showsSources) {
                        WorkshopContextSourcesView(context: context)
                            .onAppear { IslandAIWorkspace.shared.presentPopover(id: sourcesPopoverID) { showsSources = false } }
                            .onDisappear { IslandAIWorkspace.shared.clearPopover(id: sourcesPopoverID) }
                    }
            } else if images > 0 {
                Label("\(images) 项材料 · 图片", systemImage: "paperclip").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: role == "user" ? .trailing : .leading)
        .onHover { hovered = $0 }
    }
    private func copy() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

private struct WorkshopCodexThreadPicker: View {
    @ObservedObject var session: IslandAISession
    let close: () -> Void
    @ObservedObject private var preferences = IslandWidgetPreferences.shared
    @State private var search = ""
    @State private var threads: [WorkshopCodexThread] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var error = ""
    @State private var searchGeneration = UUID()
    @State private var hoveredThreadID: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { session.newConversation(); close() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil").foregroundStyle(preferences.skin.accent)
                        Text("新建对话")
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).frame(height: 32)
                    .background(preferences.skin.widgetSurface, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(IslandCardButtonStyle()).disabled(session.busy)
                .accessibilityLabel("新建 Codex 对话")
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 10))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(IslandControlStyle(role: .inline)).foregroundStyle(.secondary)
                .help("关闭对话选择").accessibilityLabel("关闭对话选择")
            }
            searchField
            Rectangle().fill(.primary.opacity(0.075)).frame(height: 0.5)
            IslandBoundedScroll(maximumHeight: min(260, max(40, IslandTaskLayout.popoverHeightLimit - 124))) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(threads) { thread in threadRow(thread) }
                    if loading {
                        ProgressView().controlSize(.mini)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    if !loading && threads.isEmpty && error.isEmpty {
                        Text(search.isEmpty ? "暂无历史对话" : "没有找到相关对话")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                    if !error.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                            Button("重试") { Task { await load() } }
                                .font(.system(size: 11)).buttonStyle(IslandControlStyle())
                                .foregroundStyle(preferences.skin.accent).disabled(loading)
                        }
                        .padding(8)
                    }
                    if cursor != nil {
                        Button("加载更多") { Task { await load(older: true) } }
                            .font(.system(size: 11)).buttonStyle(IslandControlStyle())
                            .foregroundStyle(.secondary).disabled(loading)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }
        }
        .padding(12).frame(width: 320)
        .background(preferences.skin.taskSurface)
        .environment(\.colorScheme, preferences.skin.scheme)
        .foregroundStyle(preferences.skin.primaryText, preferences.skin.secondaryText, preferences.skin.mutedText)
        .tint(preferences.skin.accent)
        .onExitCommand(perform: close)
        .onAppear { searchFocused = true }
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            await load()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("搜索历史对话", text: $search)
                .font(.system(size: 12)).textFieldStyle(.plain)
                .focused($searchFocused).focusEffectDisabled()
                .accessibilityLabel("搜索 Codex 历史对话")
            if !search.isEmpty {
                Button { search = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(IslandControlStyle(role: .inline)).foregroundStyle(.secondary)
                .accessibilityLabel("清空对话搜索")
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(preferences.skin.workspace, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(searchFocused ? preferences.skin.accent.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func threadRow(_ thread: WorkshopCodexThread) -> some View {
        let selected = session.conversation?.id == thread.id
        return Button { session.selectConversation(thread); close() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.title.isEmpty ? "未命名对话" : thread.title)
                        .font(.system(size: 12, weight: selected ? .medium : .regular)).lineLimit(1)
                    HStack(spacing: 8) {
                        Text(thread.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        if thread.busy { Text("正在执行") }
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(preferences.skin.accent)
                    .frame(width: 14).opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(selected ? preferences.skin.accent.opacity(0.08)
                        : hoveredThreadID == thread.id ? preferences.skin.hoverSurface : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandCardButtonStyle()).disabled(thread.busy || session.busy)
        .help(thread.title.isEmpty ? "未命名对话" : thread.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { inside in hoveredThreadID = inside ? thread.id : nil }
    }

    @MainActor private func load(older: Bool = false) async {
        let token = UUID(); searchGeneration = token
        loading = true; error = ""
        let cursor = older ? cursor : nil
        defer { if searchGeneration == token { loading = false } }
        do {
            let page = try await WorkshopCodexConversation().threads(cursor: cursor, search: search)
            try Task.checkCancellation()
            guard searchGeneration == token else { return }
            if older {
                let ids = Set(threads.map(\.id))
                threads += page.threads.filter { !ids.contains($0.id) }
            } else { threads = page.threads }
            self.cursor = page.nextCursor
        } catch is CancellationError {
            return
        } catch {
            guard searchGeneration == token else { return }
            self.error = String(error.localizedDescription.prefix(250))
        }
    }
}
