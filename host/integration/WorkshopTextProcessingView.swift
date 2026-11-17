import SwiftUI

struct WorkshopTextWorkbench: View {
    @ObservedObject var session: IslandAISession
    @ObservedObject private var preferences = IslandWidgetPreferences.shared
    @State private var showsSettings = false
    @State private var settingsPopoverID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sourceTitle: String {
        switch session.target {
        case "lingjian": return "灵剪"
        case "codex": return "Codex"
        case "apple": return "Apple Intelligence"
        default: return "自定义源"
        }
    }
    private var original: String { session.currentResult?.original ?? session.materials.first?.content ?? "" }
    private var contentHeight: CGFloat { min(session.textLayoutHeight, session.historyHeightLimit) }

    var body: some View {
        Group {
            if session.currentResult == nil {
                readyView
            } else {
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        let columnWidth = max(0, geometry.size.width - 27)
                        HStack(alignment: .top, spacing: 13) {
                            originalColumn.frame(width: columnWidth * 0.45)
                            Rectangle().fill(.primary.opacity(0.09)).frame(width: 1)
                                .accessibilityHidden(true)
                            translatedColumn.frame(width: columnWidth * 0.55)
                        }
                    }
                    .frame(height: contentHeight)
                    .padding(.top, WorkshopTextLayout.topInset)
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.bottom, WorkshopTextLayout.bottomInset)
            }
        }
        .onPreferenceChange(WorkshopTextHeightKey.self) { session.updateTextLayout(height: $0) }
        .foregroundStyle(.primary)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: session.currentResult == nil)
        .popover(isPresented: $showsSettings) {
            WorkshopTextSettings(session: session) { showsSettings = false }
                .onAppear { IslandAIWorkspace.shared.presentPopover(id: settingsPopoverID) { showsSettings = false } }
                .onDisappear { IslandAIWorkspace.shared.clearPopover(id: settingsPopoverID) }
        }
        .onChange(of: session.translationLanguage) { _, _ in session.textPreferencesChanged() }
        .onChange(of: session.target) { _, _ in session.textPreferencesChanged() }
        .onChange(of: session.action) { _, _ in session.textPreferencesChanged() }
    }

    private var readyView: some View {
        HStack(spacing: 12) {
            Text(session.notice.isEmpty ? "选择上方的文字卡片，开始\(session.action.title)" : session.notice)
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(preferences.skin.accent)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 22)
        .frame(height: WorkshopTextLayout.readyHeight)
        .accessibilityElement(children: .combine)
    }

    private var originalColumn: some View {
        ScrollView {
            Text(original)
                .font(.system(size: 13)).lineSpacing(6)
                .foregroundStyle(.secondary).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 7)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: WorkshopTextHeightKey.self, value: geometry.size.height)
                    }
                }
        }
        .scrollIndicators(.never)
        .frame(height: contentHeight)
        .id(session.resultID)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("原文")
    }

    private var translatedColumn: some View {
        result
            .accessibilityElement(children: .contain)
            .accessibilityLabel(session.action == .translate ? "译文" : "处理结果")
    }

    private var result: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    resultContent
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(height: 1).id("text-result-end")
                }
                .padding(.bottom, 7)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: WorkshopTextHeightKey.self, value: geometry.size.height)
                    }
                }
                .id("text-result-start")
            }
            .scrollIndicators(.never)
            .onChange(of: session.currentResult?.cacheKey) { _, _ in reader.scrollTo("text-result-start", anchor: .top) }
            .onChange(of: session.currentResult?.output) { _, _ in
                if session.busy { reader.scrollTo("text-result-end", anchor: .bottom) }
            }
        }
        .frame(height: contentHeight)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Menu {
                    if session.action.needsModel {
                        Picker("翻译源", selection: $session.target) {
                            Text("灵剪").tag("lingjian")
                            Text("Codex").tag("codex")
                            Text("自定义源").tag("compatible")
                            if ClipboardLocalModel.isAvailable || session.target == "apple" {
                                Text("Apple Intelligence").tag("apple").disabled(!ClipboardLocalModel.isAvailable)
                            }
                        }
                        Divider()
                    }
                    Button(session.action == .translate ? "翻译设置…" : "文本处理设置…") { showsSettings = true }
                } label: {
                    HStack(spacing: 5) {
                        Text(session.action.needsModel ? sourceTitle : "本机")
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .medium))
                    }
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).frame(height: 28)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("文本处理来源与设置")
                Rectangle().fill(.primary.opacity(0.10))
                    .frame(width: 1, height: 14).padding(.horizontal, 4)
                    .accessibilityHidden(true)
                Button {
                    if session.busy { session.stop() } else { session.copyResult() }
                } label: {
                    Label(session.busy ? "停止" : "复制", systemImage: session.busy ? "stop.fill" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(preferences.skin.isDark ? Color(red: 0.86, green: 0.88, blue: 0.83) : preferences.skin.clipSurface,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(ClipboardChromeButtonStyle(emphasis: .quiet, compact: true, radius: 5))
                .environment(\.colorScheme, .light)
                .disabled(!session.busy && session.currentResult?.isComplete != true)
                .help(session.busy ? "停止文本处理" : "复制结果")
                .accessibilityLabel(session.busy ? "停止文本处理" : "复制文本处理结果")
            }
            .padding(3)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.09), lineWidth: 0.7) }
        }
        .padding(.top, 9).frame(height: WorkshopTextLayout.footerHeight, alignment: .top)
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result = session.currentResult {
                if !result.output.isEmpty {
                    WorkshopAnswerView(text: result.output, sources: [], fontSize: 17)
                        .contextMenu {
                            Button("复制结果") { session.copyResult() }
                            Button("存为新片段") { session.saveResult() }
                        }
                } else if result.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini)
                        Text("正在\(session.action.title)…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if !result.error.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 11))
                        Text(result.error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        Button("重试") { session.retryResult() }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(preferences.skin.accent)
                            .buttonStyle(.plain)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if !session.notice.isEmpty { Text(session.notice).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WorkshopTextSettings: View {
    @ObservedObject var session: IslandAISession
    let close: () -> Void
    @State private var endpoint: String
    @State private var model: String
    @State private var secret = ""
    @State private var instruction: String
    @State private var error = ""

    init(session: IslandAISession, close: @escaping () -> Void) {
        self.session = session
        self.close = close
        _endpoint = State(initialValue: session.endpoint)
        _model = State(initialValue: session.model)
        _instruction = State(initialValue: session.instruction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("文本处理").font(.system(size: 14, weight: .medium))
                Spacer()
                Button("完成") { save() }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 12) {
                Picker("默认动作", selection: $session.action) {
                    ForEach(WorkshopTextTransform.allCases) { action in Text(action.title).tag(action) }
                }
                if session.action == .translate {
                    Picker("目标语言", selection: $session.translationLanguage) {
                        ForEach(WorkshopTranslationLanguage.allCases) { language in Text(language.title).tag(language) }
                    }
                }
                Picker("默认来源", selection: $session.target) {
                    Text("灵剪").tag("lingjian")
                    Text("Codex").tag("codex")
                    Text("自定义源").tag("compatible")
                    if ClipboardLocalModel.isAvailable || session.target == "apple" {
                        Text("Apple Intelligence").tag("apple").disabled(!ClipboardLocalModel.isAvailable)
                    }
                }
            }
            .padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
            if session.target == "compatible" {
                TextField("完整 chat/completions 地址", text: $endpoint)
                TextField("模型名称", text: $model)
                SecureField("API Key，留空保留已存密钥", text: $secret)
                HStack {
                    Text("密钥按接口地址保存在系统钥匙串").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Button("移除密钥") {
                        do {
                            try WorkshopModelKeychain.save("", endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
                            secret = ""
                            error = "密钥已移除"
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.plain)
                }
            }
            if session.target == "codex" {
                Text("使用本机 Codex 已登录账号调用模型服务")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if session.action == .custom {
                TextField("处理要求", text: $instruction, axis: .vertical).lineLimit(2...4)
            }
            if !error.isEmpty { Text(error).font(.system(size: 10)).foregroundStyle(.secondary) }
        }
        .font(.system(size: 11.5)).textFieldStyle(.roundedBorder)
        .padding(18).frame(width: 360).foregroundStyle(.primary)
        .onChange(of: endpoint) { _, _ in secret = ""; error = "" }
    }

    private func save() {
        do {
            guard instruction.count <= 500, session.action != .custom || !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw WorkshopError.invalid("请填写 500 字以内的处理要求。")
            }
            if session.target == "compatible" {
                let address = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
                let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try WorkshopModelConfiguration.compatibleURL(endpoint: address, model: modelName)
                if !secret.isEmpty { try WorkshopModelKeychain.save(secret, endpoint: address) }
                session.endpoint = address
                session.model = modelName
            }
            session.instruction = instruction
            session.textPreferencesChanged()
            secret = ""
            close()
        } catch { self.error = error.localizedDescription }
    }
}

private struct WorkshopTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
