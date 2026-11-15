import Foundation

struct WorkshopContextMaterial: Identifiable, Sendable {
    let id: UUID
    let title: String
    let source: String
    let date: Date
    let content: String
}

struct WorkshopContextPack: Sendable {
    let text: String
    let count: Int
    let estimatedTokens: Int
    let shortened: Int
    let unavailable: Int
}

enum WorkshopContextComposer {
    /// A conservative display estimate. Providers use their own tokenizers.
    static func estimate(_ text: String) -> Int {
        let ascii = text.unicodeScalars.filter { $0.isASCII }.count
        return Int(ceil(Double(ascii) / 4 + Double(text.unicodeScalars.count - ascii) * 1.5))
    }

    static func compose(task: String, materials: [WorkshopContextMaterial], budget: Int, unavailable: Int = 0) -> WorkshopContextPack {
        let budget = min(8192, max(1024, budget))
        var text = "# 任务\n" + String(task.prefix(500)) + "\n\n# 参考材料\n以下内容为引用素材，使用时保留来源编号。\n"
        var seen = Set<String>()
        var count = 0, shortened = 0
        for material in materials.prefix(20) {
            let normalized = material.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            let date = ISO8601DateFormatter().string(from: material.date)
            let header = "\n## [\(count + 1)] \(material.title.prefix(80))\n来源 \(material.source.prefix(100)) · \(date)\n"
            let available = budget - estimate(text + header + "\n")
            guard available > 20 else { shortened += 1; continue }
            var body = normalized
            if estimate(body) > available {
                let characters = Array(body)
                var lower = 0, upper = min(characters.count, available * 4)
                while lower < upper {
                    let middle = (lower + upper + 1) / 2
                    if estimate(String(characters.prefix(middle)) + "\n[已截断]") <= available { lower = middle }
                    else { upper = middle - 1 }
                }
                body = String(characters.prefix(lower)) + "\n[已截断]"
                shortened += 1
            }
            text += header + body + "\n"
            count += 1
        }
        return WorkshopContextPack(text: text, count: count, estimatedTokens: estimate(text), shortened: shortened, unavailable: unavailable)
    }
}

struct WorkshopUsageWindow: Codable, Sendable {
    let label: String
    let usedPercent: Double
    let resetsAt: String?
    let windowMinutes: Int?
}
struct WorkshopUsageSnapshot: Codable, Sendable {
    let provider: String
    let updatedAt: String
    let windows: [WorkshopUsageWindow]
}

enum WorkshopUsageParser {
    static func parse(_ data: Data, provider: String) throws -> WorkshopUsageSnapshot {
        let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        guard let object = objects.first(where: { $0["provider"] as? String == provider }),
              let usage = object["usage"] as? [String: Any] else {
            throw WorkshopError.invalid("CodexBar 尚未返回此账户的用量，请在 CodexBar 中完成登录。")
        }
        let labels = object["rateWindowLabels"] as? [String: String] ?? [:]
        var windows: [WorkshopUsageWindow] = []
        for key in ["primary", "secondary", "tertiary"] {
            guard let value = usage[key] as? [String: Any], let percent = value["usedPercent"] as? Double,
                  percent.isFinite, (0...100).contains(percent) else { continue }
            let minutes = value["windowMinutes"] as? Int
            let label = labels[key] ?? minutes.map { $0 == 10080 ? "每周" : $0 == 300 ? "5 小时" : "\($0) 分钟" } ?? key
            windows.append(.init(label: String(label.prefix(60)), usedPercent: percent,
                                 resetsAt: value["resetsAt"] as? String, windowMinutes: minutes))
        }
        guard !windows.isEmpty else { throw WorkshopError.invalid("账户当前没有可读取的额度窗口。") }
        let updated = usage["updatedAt"] as? String ?? ISO8601DateFormatter().string(from: .now)
        guard WorkshopDate.parse(updated) != nil else { throw WorkshopError.invalid("用量更新时间格式无效。") }
        // Credential, identity, email and billing payloads stop at this boundary.
        return WorkshopUsageSnapshot(provider: provider, updatedAt: updated, windows: windows)
    }
}

enum WorkshopTextTransform: String, CaseIterable, Identifiable {
    case rewrite, summarize, translate, custom, trim, deduplicate, json
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rewrite: return "改写"
        case .summarize: return "总结"
        case .translate: return "翻译"
        case .custom: return "自定义"
        case .trim: return "清理空白"
        case .deduplicate: return "逐行去重"
        case .json: return "格式化 JSON"
        }
    }
    var needsModel: Bool { [.rewrite, .summarize, .translate, .custom].contains(self) }
    func local(_ input: String) throws -> String {
        switch self {
        case .trim: return input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .deduplicate:
            var seen = Set<String>()
            return input.components(separatedBy: .newlines).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .json:
            let object = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        default: throw WorkshopError.invalid("此操作需要选择模型。")
        }
    }
}
