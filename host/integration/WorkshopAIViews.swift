import AppKit
import SwiftUI

struct WorkshopContextView: View {
    @ObservedObject var session: WorkshopContextSession
    @State private var candidates: [WorkshopContextMaterial] = []
    @State private var query = ""
    @State private var preview = ""
    @State private var selectedCount = 0
    @State private var summary = "选择素材后预览上下文"
    @State private var error = ""

    private var visible: [WorkshopContextMaterial] {
        candidates.filter { query.isEmpty || ($0.title + $0.content).localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("这次希望 AI 完成什么", text: $session.task).textFieldStyle(.roundedBorder)
                    .onChange(of: session.task) { _, _ in session.save(); updatePreview() }
                Picker("预算", selection: $session.budget) {
                    ForEach([1024, 2048, 4096, 8192], id: \.self) { Text("约 \($0) tokens").tag($0) }
                }.frame(width: 190)
                    .onChange(of: session.budget) { _, _ in session.save(); updatePreview() }
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        TextField("搜索最近素材", text: $query).textFieldStyle(.roundedBorder)
                        Button { load() } label: { Image(systemName: "arrow.clockwise") }.help("刷新最近 100 条")
                    }
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(visible) { item in
                                Button {
                                    session.toggle(item.id)
                                    updatePreview()
                                } label: {
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(systemName: session.selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(session.selected.contains(item.id) ? Color.accentColor : Color.secondary)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                            Text(item.content.prefix(140)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                                            Text(item.source).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.primary.opacity(session.selected.contains(item.id) ? 0.08 : 0.035), in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain).accessibilityLabel("选择素材 " + item.title)
                            }
                            if visible.isEmpty { Text("最近素材中没有匹配的文字").foregroundStyle(.secondary).padding() }
                        }
                    }.scrollIndicators(.never)
                    Text("最近 100 条 · 最多选择 20 条").font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 260).padding(.trailing, 12)
                ScrollView {
                    Text(preview).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                }.frame(minWidth: 280).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary)
                    if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
                    if !session.notice.isEmpty { Text(session.notice).foregroundStyle(.secondary) }
                }.font(.caption)
                Spacer()
                Button("清空选择") { session.selected = []; session.save(); updatePreview() }.disabled(session.selected.isEmpty)
                Button("复制上下文") {
                    let pack = session.pack()
                    preview = pack.text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pack.text, forType: .string)
                    session.notice = "已复制"
                }.buttonStyle(.borderedProminent).disabled(selectedCount == 0)
            }
        }.padding(20).foregroundStyle(.primary)
            .onAppear { load() }
            .onChange(of: session.selected) { _, _ in updatePreview() }
    }
    private func load() {
        do {
            let recent = try ClipboardLibrary.shared.widgetContextCandidates()
            let selected = session.selected.compactMap { try? ClipboardLibrary.shared.widgetContextMaterial(id: $0) }
            let selectedIDs = Set(selected.map(\.id))
            candidates = selected + recent.filter { !selectedIDs.contains($0.id) }
            error = ""
        } catch { self.error = error.localizedDescription }
        updatePreview()
    }
    private func updatePreview() {
        let pack = session.pack()
        preview = pack.text
        selectedCount = pack.count
        summary = "\(pack.count) 条素材 · 约 \(pack.estimatedTokens) tokens"
        if pack.shortened > 0 { summary += " · \(pack.shortened) 条受预算裁剪" }
        if pack.unavailable > 0 { summary += " · \(pack.unavailable) 条已不可用" }
    }
}

struct WorkshopTextView: View {
    @ObservedObject var session: WorkshopTextSession
    @State private var showsModel = false
    @State private var secret = ""
    @State private var credentialNotice = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("操作", selection: $session.action) {
                    ForEach(WorkshopTextTransform.allCases) { Text($0.title).tag($0) }
                }.frame(width: 210).disabled(session.busy)
                Spacer()
                if session.action.needsModel {
                    Button(session.provider == "apple" ? "Apple Intelligence" : session.model) { showsModel.toggle() }
                        .popover(isPresented: $showsModel) { modelSettings }.disabled(session.busy)
                } else { Text("本机处理").font(.caption).foregroundStyle(.secondary) }
                if session.busy {
                    ProgressView().controlSize(.small)
                    Button("停止") { session.cancel() }
                } else {
                    Button("处理") { session.process() }.buttonStyle(.borderedProminent).disabled(!session.ready)
                }
            }
            if [.translate, .custom].contains(session.action) {
                TextField(session.action == .translate ? "目标语言，默认简体中文" : "希望怎样处理这段文字", text: $session.instruction)
                    .textFieldStyle(.roundedBorder).disabled(session.busy)
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("原文").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("粘贴") { session.input = NSPasteboard.general.string(forType: .string) ?? "" }.disabled(session.busy)
                    }
                    TextEditor(text: $session.input).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .padding(8).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).disabled(session.busy)
                    Text("\(session.input.count) / 6000 字").font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 270).padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("结果").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("复制") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(session.output, forType: .string)
                            session.notice = "已复制"
                        }.disabled(session.output.isEmpty || session.busy)
                    }
                    TextEditor(text: $session.output).font(.system(size: 13)).scrollContentBackground(.hidden)
                        .padding(8).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10)).disabled(session.busy)
                    Text("\(session.output.count) 字").font(.caption2).foregroundStyle(.secondary)
                }.frame(minWidth: 270)
            }
            HStack {
                Text(session.action.needsModel ? (session.provider == "apple" ? ClipboardLocalModel.status : "点击处理后发送至 \(URL(string: session.endpoint)?.host ?? "所选接口")") : "文字处理在本机完成")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if ClipboardAIPrivacy.isSensitive(session.input), session.action.needsModel {
                    Text("此内容已触发隐私过滤").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(session.notice).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        }.padding(20).foregroundStyle(.primary).onDisappear { session.cancel() }
    }
    private var modelSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("模型服务", selection: $session.provider) {
                Text("Apple Intelligence").tag("apple")
                Text("OpenAI 兼容 / Ollama").tag("compatible")
            }
            if session.provider == "apple" {
                Text(ClipboardLocalModel.status).font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("完整 chat/completions 地址", text: $session.endpoint)
                TextField("模型名称", text: $session.model)
                SecureField("API Key，保存在系统钥匙串", text: $secret)
                HStack {
                    Button("保存密钥") {
                        do {
                            try WorkshopModelKeychain.save(secret.trimmingCharacters(in: .whitespacesAndNewlines), endpoint: session.endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
                            secret = ""
                            credentialNotice = "已保存到系统钥匙串"
                        } catch { credentialNotice = error.localizedDescription }
                    }.disabled(secret.isEmpty)
                    Button("移除密钥") {
                        do { try WorkshopModelKeychain.save("", endpoint: session.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)); credentialNotice = "已移除" }
                        catch { credentialNotice = error.localizedDescription }
                    }
                    Spacer()
                }
                Text("Ollama 示例\nhttp://localhost:11434/v1/chat/completions\n模型填写本机已安装的名称")
                    .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                Text(credentialNotice).font(.caption).foregroundStyle(.secondary)
            }
        }.textFieldStyle(.roundedBorder).padding(20).frame(width: 380)
            .onChange(of: session.endpoint) { _, _ in secret = ""; credentialNotice = "" }
            .onDisappear { secret = ""; session.saveModelConfiguration() }
    }
}
