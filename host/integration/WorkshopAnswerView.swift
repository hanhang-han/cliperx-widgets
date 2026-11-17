import AppKit
import MarkdownUI
import SwiftUI

struct WorkshopAnswerView: View {
    let text: String
    let sources: [WorkshopContextSource]
    var fontSize: CGFloat = 13
    @State private var selectedSource: WorkshopContextSource?
    @State private var sourcePopoverID = UUID()

    var body: some View {
        Markdown(WorkshopConversationContext.linkingCitations(in: text, sources: sources))
            .markdownTheme(.basic)
            .markdownTextStyle {
                FontSize(fontSize)
                ForegroundColor(.primary)
            }
            .markdownTextStyle(\.link) { ForegroundColor(IslandSkin.matrix.accent) }
            .markdownTextStyle(\.code) {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.94))
                BackgroundColor(.primary.opacity(0.055))
            }
            .markdownBlockStyle(\.heading1) { configuration in
                configuration.label.markdownTextStyle { FontSize(18); FontWeight(.semibold) }.markdownMargin(top: 12, bottom: 7)
            }
            .markdownBlockStyle(\.heading2) { configuration in
                configuration.label.markdownTextStyle { FontSize(16); FontWeight(.semibold) }.markdownMargin(top: 10, bottom: 6)
            }
            .markdownBlockStyle(\.heading3) { configuration in
                configuration.label.markdownTextStyle { FontSize(14); FontWeight(.semibold) }.markdownMargin(top: 9, bottom: 5)
            }
            .markdownBlockStyle(\.paragraph) { configuration in
                configuration.label.fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2)).markdownMargin(top: 0, bottom: 9)
            }
            .markdownBlockStyle(\.codeBlock) { configuration in
                WorkshopAnswerCodeBlock(code: configuration.content, language: configuration.language)
                    .markdownMargin(top: 6, bottom: 10)
            }
            .markdownBlockStyle(\.blockquote) { configuration in
                configuration.label.padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(0.18)).frame(width: 2) }
                    .markdownMargin(top: 6, bottom: 9)
            }
            .markdownBlockStyle(\.table) { configuration in
                ScrollView(.horizontal) { configuration.label.fixedSize(horizontal: true, vertical: false) }
                    .scrollIndicators(.never).markdownMargin(top: 6, bottom: 10)
            }
            .markdownBlockStyle(\.thematicBreak) { Divider().opacity(0.4).markdownMargin(top: 10, bottom: 10) }
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "cliperx-source" else { return .systemAction }
                let source: WorkshopContextSource?
                if let raw = url.host, let id = UUID(uuidString: raw) {
                    source = sources.first { $0.clipboardID == id }
                } else if url.host == "reference", let label = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "label" })?.value {
                    source = sources.first { $0.label == label }
                } else {
                    source = nil
                }
                guard let source else {
                    ClipboardMonitor.shared.showToast("这条引文的来源信息暂不可用。", duration: 2)
                    return .handled
                }
                if !IslandAIWorkspace.shared.revealCitation(source) {
                    selectedSource = source
                    ClipboardMonitor.shared.showToast("这条历史引文保留了预览，缺少原始定位信息。", duration: 2)
                }
                return .handled
            })
            .popover(isPresented: Binding(get: { selectedSource != nil }, set: { if !$0 { selectedSource = nil } })) {
                if let source = selectedSource {
                    WorkshopContextSourcePreview(source: source)
                        .onAppear { IslandAIWorkspace.shared.presentPopover(id: sourcePopoverID) { selectedSource = nil } }
                        .onDisappear { IslandAIWorkspace.shared.clearPopover(id: sourcePopoverID) }
                }
            }
    }
}

private struct WorkshopAnswerCodeBlock: View {
    let code: String
    let language: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let language, !language.isEmpty { Text(language).font(.system(size: 9.5)).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10)).frame(width: 20, height: 20)
                }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("复制代码").help("复制代码")
            }
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.primary)
                    .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
            }.scrollIndicators(.never)
        }.padding(10).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WorkshopContextSourcesView: View {
    let context: WorkshopConversationContext
    @State private var selected: WorkshopContextSource?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selected {
                Button { self.selected = nil } label: { Label("全部材料", systemImage: "chevron.left").font(.system(size: 10.5)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                WorkshopContextSourcePreview(source: selected, inset: false)
            } else {
                Text("\(context.sources.count) 项材料").font(.system(size: 12, weight: .medium))
                Text(context.summary).font(.system(size: 10)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(context.sources) { source in
                            Button { selected = source } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: source.isImage ? "photo" : "doc.text").font(.system(size: 12)).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(source.title).font(.system(size: 11.5)).lineLimit(2)
                                        Text(source.source).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }.padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 240).scrollIndicators(.never)
            }
        }.padding(16).frame(width: 340).foregroundStyle(.primary)
    }
}

struct WorkshopContextSourcePreview: View {
    let source: WorkshopContextSource
    var inset = true
    @State private var material: WorkshopContextMaterial?
    @State private var legacyImage: NSImage?
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(source.title).font(.system(size: 12, weight: .medium)).lineLimit(3)
            if let image = material?.imageData.flatMap(NSImage.init(data:)) ?? legacyImage {
                Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 280)
            } else if let text = material?.content ?? source.preview, !source.isImage {
                ScrollView { Text(text).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 260).scrollIndicators(.never)
            } else if !message.isEmpty {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
            } else { ProgressView().controlSize(.mini) }
            Text(source.source).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(inset ? 16 : 0).frame(width: inset ? 350 : nil).foregroundStyle(.primary)
        .task(id: source.id) {
            material = nil; legacyImage = nil; message = ""
            if let id = source.clipboardID {
                do { material = try ClipboardLibrary.shared.widgetContextMaterial(id: id, includeImages: true) }
                catch { message = "该材料已删除或当前无法读取。" }
            } else if source.isImage, let path = source.imagePath {
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("com.clipnote.app/WidgetWorkshop/Codex/Media").resolvingSymlinksInPath()
                let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                if file.path.hasPrefix(directory.path + "/"), file.pathExtension == "png" {
                    legacyImage = NSImage(contentsOf: file)
                }
                if legacyImage == nil { message = "这张历史图片的原始预览暂不可用。" }
            } else if source.preview == nil { message = "这条历史材料的原始预览暂不可用。" }
        }
    }
}
