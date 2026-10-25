import Foundation

enum L10n {
    /// 使う人の言語設定の先頭が日本語なら日本語、それ以外は英語
    static let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
    static func t(_ ja: String, _ en: String) -> String { isJapanese ? ja : en }
}
