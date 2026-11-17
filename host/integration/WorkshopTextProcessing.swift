import CryptoKit
import Foundation
import NaturalLanguage

enum WorkshopTextLayout {
    static let readyHeight: CGFloat = 75
    static let footerHeight: CGFloat = 45
    static let topInset: CGFloat = 18
    static let bottomInset: CGFloat = 16
    static let minimumResultHeight: CGFloat = 48
    static let controlsHeight = footerHeight + topInset + bottomInset
}

enum WorkshopTranslationLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic, simplifiedChinese, english, traditionalChinese, japanese, korean, french, german, spanish

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "中英互译"
        case .simplifiedChinese: return "简体中文"
        case .english: return "英语"
        case .traditionalChinese: return "繁体中文"
        case .japanese: return "日语"
        case .korean: return "韩语"
        case .french: return "法语"
        case .german: return "德语"
        case .spanish: return "西班牙语"
        }
    }

    func target(for text: String) -> String {
        guard self == .automatic else { return title }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(6000)))
        switch recognizer.dominantLanguage {
        case .simplifiedChinese, .traditionalChinese: return "英语"
        default: return "简体中文"
        }
    }

}

struct WorkshopTextRequest: Sendable {
    let input: String
    let action: WorkshopTextTransform
    let instruction: String
    let cacheKey: String

    init(input: String, action: WorkshopTextTransform, language: WorkshopTranslationLanguage,
         instruction: String, provider: String, endpoint: String, model: String, secret: String) throws {
        self.input = input
        self.action = action
        self.instruction = action == .translate ? language.target(for: input) : instruction
        let values = [input, action.rawValue, self.instruction, provider, endpoint, model, secret]
        cacheKey = SHA256.hash(data: try JSONEncoder().encode(values)).map { String(format: "%02x", $0) }.joined()
    }
}

struct WorkshopTextStream {
    private(set) var text = ""
    private(set) var finished = false

    mutating func accept(_ payload: String) throws {
        if payload == "[DONE]" { finished = true; return }
        guard let data = payload.data(using: .utf8),
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WorkshopError.invalid("翻译源返回的数据格式无效。")
        }
        if value["type"] as? String == "error" {
            throw WorkshopError.invalid(String((value["message"] as? String ?? "翻译源暂时不可用。").prefix(400)))
        }
        if let error = value["error"] {
            let message = (error as? [String: Any])?["message"] as? String ?? error as? String ?? "翻译源暂时不可用。"
            throw WorkshopError.invalid(String(message.prefix(400)))
        }
        if value["type"] as? String == "done" { finished = true }
        if value["type"] as? String == "text", let delta = value["content"] as? String { text += delta }
        if let choice = (value["choices"] as? [[String: Any]])?.first {
            if let delta = (choice["delta"] as? [String: Any])?["content"] as? String { text += delta }
            if let content = (choice["message"] as? [String: Any])?["content"] as? String {
                text = content
                finished = true
            }
            if let reason = choice["finish_reason"] as? String {
                guard reason == "stop" else { throw WorkshopError.invalid("处理结果被截断或拦截，请缩短原文后重试。") }
                finished = true
            }
        }
        guard text.count <= 20000 else { throw WorkshopError.invalid("处理结果超过 20000 字，请缩短原文后重试。") }
    }
}
