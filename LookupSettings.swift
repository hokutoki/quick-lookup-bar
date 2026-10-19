import Foundation

enum SettingsError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

enum BuiltinLookupRoute: String, Codable, CaseIterable {
    case monokakido, chatGPTWeb, claude, grok, google, chatGPTDot, grokBot

    var targetID: String {
        switch self {
        case .chatGPTWeb: return "chatgpt-web"
        case .chatGPTDot: return "chatgpt-dot"
        case .grokBot: return "grok-bot"
        default: return rawValue
        }
    }
}

enum LookupRoute: Codable, Equatable {
    case builtin(BuiltinLookupRoute)
    case httpsTemplate(String)

    func makeURL(query: String) throws -> URL? {
        switch self {
        case .httpsTemplate(let template): return try HTTPSQueryTemplate(template).url(query: query)
        case .builtin(let kind):
            switch kind {
            case .chatGPTDot, .grokBot: return nil
            case .monokakido:
                var components = URLComponents()
                components.scheme = "mkdictionaries"
                components.host = ""
                components.path = "/"
                components.queryItems = [URLQueryItem(name: "text", value: query), URLQueryItem(name: "type", value: "starts-with")]
                return try encodedURL(components)
            case .chatGPTWeb: return try HTTPSQueryTemplate("https://chatgpt.com/?q={query}").url(query: query)
            case .claude: return try HTTPSQueryTemplate("https://claude.ai/new?q={query}").url(query: query)
            case .grok: return try HTTPSQueryTemplate("https://grok.com/?q={query}").url(query: query)
            case .google: return try HTTPSQueryTemplate("https://www.google.com/search?q={query}").url(query: query)
            }
        }
    }
}

// Query values use the unreserved set so form decoders cannot turn a literal + into a space.
private func encodedURL(_ original: URLComponents) throws -> URL {
    var components = original
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    if let items = components.queryItems {
        components.percentEncodedQuery = items.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed)!
            return name + (item.value.map { "=" + $0.addingPercentEncoding(withAllowedCharacters: allowed)! } ?? "")
        }.joined(separator: "&")
    }
    guard let result = components.url else { throw SettingsError.invalid("検索URLを作成できません。") }
    return result
}

struct HTTPSQueryTemplate {
    let components: URLComponents

    init(_ template: String) throws {
        guard !template.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              template.components(separatedBy: "{query}").count == 2,
              let parts = URLComponents(string: template.replacingOccurrences(of: "{query}", with: "%7Bquery%7D")),
              parts.scheme?.lowercased() == "https",
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              !(parts.host ?? "").contains("{query}"),
              !parts.path.contains("{query}"),
              !(parts.fragment ?? "").contains("{query}"),
              let items = parts.queryItems,
              items.filter({ $0.value?.contains("{query}") == true }).count == 1,
              !items.contains(where: { $0.name.contains("{query}") }) else {
            throw SettingsError.invalid("HTTPS URLのクエリ値に {query} を1個指定してください。ユーザー情報や制御文字は使えません。")
        }
        // Reject encoded extra placeholders as well as replacements in paths or query names.
        let decodedFields = [parts.host ?? "", parts.path, parts.fragment ?? ""] + items.map(\.name) + items.compactMap(\.value)
        guard !decodedFields.contains(where: { $0.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) }),
              decodedFields.reduce(0, { $0 + $1.components(separatedBy: "{query}").count - 1 }) == 1 else {
            throw SettingsError.invalid("{query} はクエリ値の1箇所だけに指定してください。")
        }
        components = parts
    }

    func url(query: String) throws -> URL {
        var parts = components
        parts.queryItems = parts.queryItems?.map { item in
            URLQueryItem(name: item.name, value: item.value?.replacingOccurrences(of: "{query}", with: query))
        }
        return try encodedURL(parts)
    }
}

struct LookupTarget: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var enabled: Bool = true
    var shortcut: Int?
    var route: LookupRoute

    var isBuiltin: Bool { if case .builtin = route { return true }; return false }
    var symbolName: String {
        switch route {
        case .httpsTemplate: return "globe"
        case .builtin(let kind):
            switch kind {
            case .monokakido: return "character.book.closed"
            case .chatGPTWeb: return "bubble.left.and.bubble.right"
            case .claude: return "sparkles"
            case .grok: return "bolt"
            case .google: return "magnifyingglass"
            case .chatGPTDot: return "bubble.left"
            case .grokBot: return "app"
            }
        }
    }
    func makeURL(query: String) throws -> URL? { try route.makeURL(query: query) }
}

struct AppSettings: Codable, Equatable {
    var version: Int = 1
    var targets: [LookupTarget]
    var defaultTargetID: String
    var showMenuBarIcon: Bool = false

    static let defaults = AppSettings(targets: [
        LookupTarget(id: "monokakido", name: "物書堂", shortcut: 1, route: .builtin(.monokakido)),
        LookupTarget(id: "chatgpt-web", name: "ChatGPT Web", shortcut: 2, route: .builtin(.chatGPTWeb)),
        LookupTarget(id: "claude", name: "Claude", shortcut: 3, route: .builtin(.claude)),
        LookupTarget(id: "grok", name: "Grok", shortcut: 4, route: .builtin(.grok)),
        LookupTarget(id: "google", name: "Google", shortcut: 5, route: .builtin(.google)),
        LookupTarget(id: "chatgpt-dot", name: "ChatGPT dot", shortcut: 6, route: .builtin(.chatGPTDot)),
        LookupTarget(id: "grok-bot", name: "Grok Bot", shortcut: 7, route: .builtin(.grokBot))
    ], defaultTargetID: "monokakido")

    var enabledTargets: [LookupTarget] { targets.filter(\.enabled) }
    var defaultTarget: LookupTarget? { targets.first { $0.id == defaultTargetID && $0.enabled } }

    @discardableResult func validated() throws -> AppSettings {
        guard version == 1 else { throw SettingsError.invalid("このバージョンの設定は読み込めません。元の設定は保持しています。") }
        guard targets.count <= 100 else { throw SettingsError.invalid("検索先は100件までです。") }
        guard Set(targets.map(\.id)).count == targets.count,
              !targets.contains(where: { $0.id.isEmpty }) else { throw SettingsError.invalid("検索先IDが空か重複しています。") }
        var shortcuts = Set<Int>()
        for target in targets {
            let name = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, target.name.count <= 40,
                  !target.name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw SettingsError.invalid("検索先の名前は空白だけにせず、40文字以内で入力してください。")
            }
            if let shortcut = target.shortcut {
                guard (1...9).contains(shortcut), shortcut != 8, shortcuts.insert(shortcut).inserted else {
                    throw SettingsError.invalid("キーは1〜7または9を重複せず指定してください。8は音声入力用です。")
                }
            }
            switch target.route {
            case .httpsTemplate(let template):
                guard !BuiltinLookupRoute.allCases.contains(where: { $0.targetID == target.id }) else {
                    throw SettingsError.invalid("標準検索先の接続方式は変更できません。")
                }
                _ = try HTTPSQueryTemplate(template)
            case .builtin(let kind):
                guard kind.targetID == target.id else { throw SettingsError.invalid("標準検索先のIDと接続方式が一致していません。") }
            }
        }
        for kind in BuiltinLookupRoute.allCases {
            guard targets.contains(where: { $0.id == kind.targetID && $0.route == .builtin(kind) }) else {
                throw SettingsError.invalid("標準検索先は削除できません。使わない検索先は無効にしてください。")
            }
        }
        guard !enabledTargets.isEmpty else { throw SettingsError.invalid("検索先を1件以上有効にしてください。") }
        guard defaultTarget != nil else { throw SettingsError.invalid("有効な検索先を初期検索先に指定してください。") }
        return self
    }
}

final class SettingsStore {
    static let storageKey = "QuickLookupBar.settings.v1"
    private let defaults: UserDefaults
    private let key: String
    private(set) var settings = AppSettings.defaults
    private(set) var loadError: String?

    init(defaults: UserDefaults = .standard, key: String = SettingsStore.storageKey) {
        self.defaults = defaults
        self.key = key
        guard let object = defaults.object(forKey: key) else { return }
        guard let data = object as? Data else {
            loadError = "保存設定を読み込めなかったため、標準設定で起動しました。元の設定は保持しています。"
            return
        }
        do { settings = try JSONDecoder().decode(AppSettings.self, from: data).validated() }
        catch { loadError = "保存設定を読み込めなかったため、標準設定で起動しました。元の設定は保持しています。\n" + error.localizedDescription }
    }

    func save(_ snapshot: AppSettings) throws {
        let valid = try snapshot.validated()
        let data = try JSONEncoder().encode(valid)
        defaults.set(data, forKey: key)
        settings = valid
        loadError = nil
    }

    static func newCustomTarget(name: String = "新しい検索先", template: String = "https://example.com/search?q={query}", shortcut: Int? = nil) -> LookupTarget {
        LookupTarget(id: "custom-" + UUID().uuidString.lowercased(), name: name, shortcut: shortcut, route: .httpsTemplate(template))
    }
}
