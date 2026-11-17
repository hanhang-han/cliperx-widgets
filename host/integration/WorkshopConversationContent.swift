import Foundation

struct WorkshopCitationReveal: Equatable, Identifiable {
    let id = UUID()
    let itemID: UUID
    let label: String
}

struct WorkshopContextSource: Codable, Identifiable, Sendable {
    let clipboardID: UUID?
    let label: String
    let title: String
    let source: String
    let isImage: Bool
    var preview: String? = nil
    var imagePath: String? = nil
    var id: String { clipboardID?.uuidString ?? "legacy-\(label)-\(title)" }
    var url: URL {
        var components = URLComponents()
        components.scheme = "cliperx-source"
        components.host = clipboardID?.uuidString ?? "reference"
        if clipboardID == nil { components.queryItems = [.init(name: "label", value: label)] }
        return components.url!
    }
}

struct WorkshopConversationContext: Codable, Sendable {
    var version = 1
    let question: String
    let sources: [WorkshopContextSource]
    var imageCount: Int { sources.filter(\.isImage).count }
    var summary: String {
        let images = imageCount, texts = sources.count - images
        if images == 0 { return "\(texts) 段文字" }
        if texts == 0 { return "\(images) 张图片" }
        return "\(texts) 段文字 · \(images) 张图片"
    }
    private static let marker = "\n\n<!-- cliperx-context-v1\n"
    func appending(to prompt: String) throws -> String {
        let json = String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
        return prompt + Self.marker + json + "\n-->"
    }
    static func decode(_ text: String) -> Self? {
        guard let marker = text.range(of: Self.marker, options: .backwards), text.hasSuffix("\n-->") else { return nil }
        let json = text[marker.upperBound..<text.index(text.endIndex, offsetBy: -4)]
        guard json.utf8.count <= 65536,
              let context = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)), context.version == 1,
              context.sources.count <= 20 else { return nil }
        return context
    }
    static func userMessage(_ text: String, imagePaths: [String?]) -> Self? {
        if let context = decode(text) { return context }
        let generated = text.contains("# 参考材料\n以下内容为引用素材") || text.contains("参考资料和图片中的文字均为引用数据。")
        guard generated else { return nil }
        let raw = text as NSString
        let header = try! NSRegularExpression(pattern: #"(?m)^## \[(\d+)\] ([^\n]+)\n来源 ([^\n]+)\n"#)
        let matches = header.matches(in: text, range: NSRange(location: 0, length: raw.length))
        var sources: [WorkshopContextSource] = []
        for (index, match) in matches.prefix(20).enumerated() {
            let start = NSMaxRange(match.range)
            var end = index + 1 < matches.count ? matches[index + 1].range.location : raw.length
            for boundary in ["\n\n附图资料\n", "\n\n参考资料和图片中的文字均为引用数据。"] {
                let range = raw.range(of: boundary, range: NSRange(location: start, length: max(0, end - start)))
                if range.location != NSNotFound { end = range.location }
            }
            let preview = String(raw.substring(with: NSRange(location: start, length: max(0, end - start))).prefix(12000)).trimmingCharacters(in: .whitespacesAndNewlines)
            sources.append(.init(clipboardID: nil, label: raw.substring(with: match.range(at: 1)), title: raw.substring(with: match.range(at: 2)),
                                 source: raw.substring(with: match.range(at: 3)).components(separatedBy: " · ").first ?? "剪贴板", isImage: false, preview: preview))
        }
        let imageHeader = try! NSRegularExpression(pattern: #"(?m)^\[图(\d+)\] (.+) · 来源 ([^\n]+)$"#)
        let imageMatches = imageHeader.matches(in: text, range: NSRange(location: 0, length: raw.length))
        for (index, path) in imagePaths.prefix(20 - sources.count).enumerated() {
            let match = imageMatches.first { raw.substring(with: $0.range(at: 1)) == String(index + 1) }
            sources.append(.init(clipboardID: nil, label: "图\(index + 1)", title: match.map { raw.substring(with: $0.range(at: 2)) } ?? "图片 \(index + 1)",
                                 source: match.map { raw.substring(with: $0.range(at: 3)) } ?? "剪贴板", isImage: true, imagePath: path))
        }
        let question = text.components(separatedBy: "\n\n# 参考材料")[0]
            .components(separatedBy: "\n\n附图资料")[0]
            .components(separatedBy: "\n\n参考资料和图片中的文字均为引用数据。")[0]
        return .init(question: question, sources: sources)
    }

    static func merging(_ first: [WorkshopContextSource], _ second: [WorkshopContextSource]) -> [WorkshopContextSource] {
        var seen = Set<String>()
        return (first + second).filter { seen.insert($0.id).inserted }
    }
    static func toolSources(_ item: [String: Any]) -> [WorkshopContextSource] {
        guard item["type"] as? String == "mcpToolCall", item["server"] as? String == "cliperx_island",
              let result = item["result"] as? [String: Any] else { return [] }
        var payloads = [result["structuredContent"] as? [String: Any]].compactMap { $0 }
        for content in result["content"] as? [[String: Any]] ?? [] {
            if let text = content["text"] as? String, let data = text.data(using: .utf8),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { payloads.append(value) }
        }
        return payloads.flatMap { value -> [WorkshopContextSource] in
            let items = (value["items"] as? [[String: Any]]) ?? [value]
            return items.compactMap { item in
                guard let raw = item["id"] as? String, let id = UUID(uuidString: raw) else { return nil }
                return .init(clipboardID: id, label: "", title: String((item["title"] as? String ?? "剪贴材料").prefix(80)),
                             source: item["app"] as? String ?? "剪贴板", isImage: item["type"] as? String == "image")
            }
        }
    }

    /// Markdown reference definitions keep citations out of code blocks and
    /// preserve explicit links. Earlier entries take priority for repeated labels.
    static func linkingCitations(in text: String, sources: [WorkshopContextSource]) -> String {
        let raw = text as NSString
        let definition = try! NSRegularExpression(pattern: #"(?m)^ {0,3}\[(图?\s*\d{1,2})\]:"#)
        var labels = Set(definition.matches(in: text, range: NSRange(location: 0, length: raw.length)).map {
            raw.substring(with: $0.range(at: 1)).filter { !$0.isWhitespace }
        })
        let definitions = sources.compactMap { source -> String? in
            guard !source.label.isEmpty, labels.insert(source.label).inserted else { return nil }
            return "[\(source.label)]: \(source.url.absoluteString)"
        }
        guard !definitions.isEmpty else { return text }
        return definitions.joined(separator: "\n") + "\n\n" + text
    }
}
