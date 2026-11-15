import Foundation

enum WorkshopError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

struct WorkshopPermissions: Codable, Equatable, Sendable {
    var network: [String] = []
    var openURL = false
    var clipboardWrite = false
    var systemMetrics = false
    var contextPreparation = false
    var textProcessing = false
    var aiUsage = false

    private enum CodingKeys: String, CodingKey { case network, openURL, clipboardWrite, systemMetrics, contextPreparation, textProcessing, aiUsage }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        network = try values.decodeIfPresent([String].self, forKey: .network) ?? []
        openURL = try values.decodeIfPresent(Bool.self, forKey: .openURL) ?? false
        clipboardWrite = try values.decodeIfPresent(Bool.self, forKey: .clipboardWrite) ?? false
        systemMetrics = try values.decodeIfPresent(Bool.self, forKey: .systemMetrics) ?? false
        contextPreparation = try values.decodeIfPresent(Bool.self, forKey: .contextPreparation) ?? false
        textProcessing = try values.decodeIfPresent(Bool.self, forKey: .textProcessing) ?? false
        aiUsage = try values.decodeIfPresent(Bool.self, forKey: .aiUsage) ?? false
    }

    var summary: String {
        var parts = network.isEmpty ? [] : ["访问 " + network.joined(separator: "、")]
        if openURL { parts.append("点击后打开网页") }
        if clipboardWrite { parts.append("点击后写入剪贴板") }
        if systemMetrics { parts.append("读取系统性能数据") }
        if contextPreparation { parts.append("打开原生上下文选材，读取选材数量与估算用量") }
        if textProcessing { parts.append("打开原生文字处理，模型与发送内容由用户选择") }
        if aiUsage { parts.append("通过本机 CodexBar 读取标准化用量与重置时间") }
        return parts.isEmpty ? "本地计算与组件独立存储" : parts.joined(separator: "\n")
    }
}

struct WorkshopSetting: Codable, Equatable, Identifiable, Sendable {
    let key: String
    let title: String
    let defaultValue: String
    var id: String { key }
    private enum CodingKeys: String, CodingKey { case key, title; case defaultValue = "default" }
}

struct WorkshopHTTPSource: Codable, Equatable, Sendable {
    let url: String
}

struct WorkshopManifest: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let apiVersion: Int
    let author: String
    let description: String
    let license: String
    let symbol: String
    let sizes: [String]
    let refreshSeconds: Int
    let permissions: WorkshopPermissions
    let settings: [WorkshopSetting]?
    let sources: [String: WorkshopHTTPSource]?

    var defaultSettings: [String: String] {
        Dictionary((settings ?? []).map { ($0.key, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
    }

    func validate() throws {
        guard [1, 2].contains(apiVersion) else { throw WorkshopError.invalid("组件需要其他版本的开发 API。") }
        guard apiVersion >= 2 || !(permissions.contextPreparation || permissions.textProcessing || permissions.aiUsage) else {
            throw WorkshopError.invalid("AI 能力需要 Widget API 2。")
        }
        guard Self.validID(id), id.utf8.count <= 100 else { throw WorkshopError.invalid("组件 ID 格式无效。") }
        guard version.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil else {
            throw WorkshopError.invalid("版本号应为 x.y.z。")
        }
        guard !name.isEmpty, name.count <= 60, !author.isEmpty, author.count <= 80,
              !description.isEmpty, description.count <= 300, !license.isEmpty, license.count <= 80,
              !symbol.isEmpty, symbol.count <= 80 else { throw WorkshopError.invalid("组件说明、作者或图标无效。") }
        guard !sizes.isEmpty, sizes.count <= 2, Set(sizes).count == sizes.count,
              sizes.allSatisfy({ ["small", "wide"].contains($0) }), (10...86400).contains(refreshSeconds) else {
            throw WorkshopError.invalid("组件尺寸或刷新间隔无效，刷新间隔为 10～86400 秒。")
        }
        guard permissions.network.count <= 8,
              permissions.network.allSatisfy(Self.validNetworkHost) else { throw WorkshopError.invalid("网络权限应填写明确的 HTTPS 域名。") }
        let fields = settings ?? []
        guard fields.count <= 12, Set(fields.map(\.key)).count == fields.count,
              fields.allSatisfy({ Self.validKey($0.key) && !$0.title.isEmpty && $0.title.count <= 60 && $0.defaultValue.count <= 500 }) else {
            throw WorkshopError.invalid("组件配置项无效。")
        }
        guard (sources ?? [:]).count <= 4 else { throw WorkshopError.invalid("最多声明四个网络数据源。") }
        for (key, source) in sources ?? [:] {
            guard Self.validKey(key), source.url.utf8.count <= 2048 else { throw WorkshopError.invalid("数据源格式无效。") }
            _ = try sourceURL(source, settings: defaultSettings)
        }
    }

    func sourceURL(_ source: WorkshopHTTPSource, settings values: [String: String]) throws -> URL {
        var template = source.url
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for field in settings ?? [] {
            let value = values[field.key] ?? field.defaultValue
            guard value.count <= 500 else { throw WorkshopError.invalid("配置内容过长。") }
            template = template.replacingOccurrences(of: "{{\(field.key)}}", with: value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        guard !template.contains("{{"), let url = URL(string: template), url.scheme == "https",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), Self.validNetworkHost(host),
              permissions.network.contains(host) else { throw WorkshopError.invalid("数据源地址超出组件声明的网络权限。") }
        return url
    }

    static func validID(_ value: String) -> Bool {
        value.range(of: #"^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$"#, options: .regularExpression) != nil
    }
    static func validKey(_ value: String) -> Bool {
        value.range(of: #"^[a-zA-Z][a-zA-Z0-9_]{0,39}$"#, options: .regularExpression) != nil
    }
    static func validNetworkHost(_ value: String) -> Bool {
        value == value.lowercased() && value.count <= 253 && !value.hasSuffix(".local")
            && value.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$"#, options: .regularExpression) != nil
    }
}

struct WorkshopPackage: Codable, Sendable {
    let formatVersion: Int
    let manifest: WorkshopManifest
    let script: String

    func validate() throws {
        guard formatVersion == 1, !script.isEmpty, script.utf8.count <= 131072 else {
            throw WorkshopError.invalid("组件包格式无效或脚本超过 128 KB。")
        }
        try manifest.validate()
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 262144 else { throw WorkshopError.invalid("组件包超过 256 KB。") }
        let package = try JSONDecoder().decode(Self.self, from: data)
        try package.validate()
        return package
    }
}

struct WorkshopCatalog: Codable, Sendable {
    let schemaVersion: Int
    let widgets: [WorkshopCatalogEntry]
}

struct WorkshopCatalogEntry: Codable, Identifiable, Sendable {
    let manifest: WorkshopManifest
    let packageURL: URL
    let sha256: String
    let sourceURL: URL
    var id: String { manifest.id }

    func validate() throws {
        try manifest.validate()
        guard packageURL.scheme == "https", sourceURL.scheme == "https",
              packageURL.user == nil, packageURL.password == nil,
              packageURL.host == "github.com" || packageURL.host == "raw.githubusercontent.com",
              sha256.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw WorkshopError.invalid("工坊下载地址或校验值无效。")
        }
    }
}

indirect enum WorkshopJSON: Codable, Sendable {
    case object([String: WorkshopJSON]), array([WorkshopJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: WorkshopJSON].self) { self = .object(value) }
        else { self = .array(try container.decode([WorkshopJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct WorkshopAction: Codable, Identifiable, Sendable {
    let id: String
    let title: String
}
struct WorkshopDetailRow: Codable, Identifiable, Sendable {
    let label: String
    let value: String
    var id: String { label }
}
enum WorkshopDate {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
struct WorkshopSnapshot: Codable, Sendable {
    let title: String
    let value: String
    let subtitle: String?
    let symbol: String?
    let progress: Double?
    let series: [Double]?
    let countdownTo: String?
    let details: [WorkshopDetailRow]?
    let actions: [WorkshopAction]?

    func validate() throws {
        guard title.count <= 60, value.count <= 120, (subtitle?.count ?? 0) <= 180,
              (symbol?.count ?? 0) <= 80, (series?.count ?? 0) <= 60,
              (series ?? []).allSatisfy(\.isFinite), (details?.count ?? 0) <= 20,
              (details ?? []).allSatisfy({ $0.label.count <= 80 && $0.value.count <= 500 }),
              Set((details ?? []).map(\.label)).count == (details?.count ?? 0),
              (actions?.count ?? 0) <= 4,
              (actions ?? []).allSatisfy({ WorkshopManifest.validKey($0.id) && !$0.title.isEmpty && $0.title.count <= 40 }),
              Set((actions ?? []).map(\.id)).count == (actions?.count ?? 0) else {
            throw WorkshopError.invalid("组件返回的卡片内容超出协议限制。")
        }
        if let progress, !progress.isFinite || !(0...1).contains(progress) { throw WorkshopError.invalid("进度值应为 0～1。") }
        if let countdownTo, WorkshopDate.parse(countdownTo) == nil { throw WorkshopError.invalid("倒计时时间应为 ISO 8601 格式。") }
    }
}

struct WorkshopEffect: Codable, Sendable {
    let type: String
    let value: String
}
struct WorkshopResult: Codable, Sendable {
    let view: WorkshopSnapshot
    let state: [String: WorkshopJSON]
    let effects: [WorkshopEffect]
}

/// The runner receives only JSON and JavaScript through stdin. It has no host API bridge.
enum WorkshopScriptProtocol {
    static let bootstrap = """
    var __widgetDefinition;
    function defineWidget(definition) { __widgetDefinition = definition; }
    """
    static let evaluate = """
    (function () {
      if (!__widgetDefinition || typeof __widgetDefinition.render !== 'function') {
        throw new Error('Call defineWidget({ render(context) { ... } })');
      }
      var effects = [];
      if (__action !== null) {
        if (typeof __widgetDefinition.onAction !== 'function') throw new Error('Missing onAction');
        var update = __widgetDefinition.onAction(__action, __context) || {};
        if (update.state !== undefined) __context.state = update.state;
        effects = update.effects || [];
      }
      return JSON.stringify({ view: __widgetDefinition.render(__context), state: __context.state, effects: effects });
    })()
    """
}
