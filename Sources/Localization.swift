import Foundation

enum AppLanguage: String, CaseIterable {
    case simplifiedChinese = "zh-Hans", english = "en"
    static let preferenceKey = "displayLanguage"
    static var current: AppLanguage { load(from: .standard) }
    static func load(from defaults: UserDefaults) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: preferenceKey) ?? "") ?? .simplifiedChinese
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
    var locale: Locale { Locale(identifier: self == .english ? "en_US" : "zh_CN") }
}
struct Translator {
    let english: [String: String]
    func text(_ key: String, _ args: [String] = [], language: AppLanguage) -> String {
        let template = language == .english ? english[key] ?? key : key
        // Interpolate only the original template. Chat names may contain braces or percent signs.
        let expression = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
        let source = template as NSString
        var result = "", offset = 0
        for match in expression.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            let index = Int(source.substring(with: match.range(at: 1))) ?? -1
            result += args.indices.contains(index) ? args[index] : source.substring(with: match.range)
            offset = NSMaxRange(match.range)
        }
        return result + source.substring(from: offset)
    }
}
private let translator: Translator = {
    let url = Bundle.main.url(forResource: "en", withExtension: "json", subdirectory: "Localization")
    let data = url.flatMap { try? Data(contentsOf: $0) }
    let entries = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    return Translator(english: entries)
}()
func L(_ key: String, _ arguments: String...) -> String { translator.text(key, arguments, language: .current) }
