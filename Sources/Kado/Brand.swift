import AppKit

/// アプリの名前・色・記号。build.sh が brand/*.env の値を Info.plist に書き込み、ここで読む。
/// 公開版と手元用（local/brand.env）で見た目を変えるため、コードには名前や色を直接書かない。
enum Brand {
    private static let info = Bundle.main.infoDictionary ?? [:]

    /// 画面に出す名前
    static let displayName = info["CFBundleDisplayName"] as? String ?? "Kado"

    /// 内部の名前（作業フォルダの名前などに使う）
    static let appName = info["CFBundleName"] as? String ?? "Kado"

    /// kado:// のような、外から呼び出すための URL スキーム
    static let urlScheme: String = {
        let types = info["CFBundleURLTypes"] as? [[String: Any]]
        let schemes = types?.first?["CFBundleURLSchemes"] as? [String]
        return schemes?.first ?? "kado"
    }()

    /// アクセントカラー（#RRGGBB）
    static let accent = color(hex: info["BrandAccentColor"] as? String ?? "#4C5BD4")

    /// バブルとメニューバーに出す SF Symbol
    static let symbol = info["BrandSymbol"] as? String ?? "bubble.left.fill"

    private static func color(hex: String) -> NSColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .controlAccentColor }
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
