import Foundation

enum ModelChoice: String, CaseIterable, Identifiable {
    case haiku, sonnet, opus

    var id: String { rawValue }

    /// claude --model に渡す名前
    var cliName: String { rawValue }

    /// claude --effort に渡す値。Haiku は省略の多い質問も読み取れるよう、少し考えさせる
    var effort: String {
        switch self {
        case .haiku: return "medium"
        case .sonnet, .opus: return "low"
        }
    }

    var label: String {
        switch self {
        case .haiku: return L10n.t("Haiku（速い）", "Haiku (Fast)")
        case .sonnet: return L10n.t("Sonnet（ふつう）", "Sonnet (Balanced)")
        case .opus: return L10n.t("Opus（じっくり）", "Opus (Thorough)")
        }
    }

    var shortLabel: String {
        switch self {
        case .haiku: return "Haiku"
        case .sonnet: return "Sonnet"
        case .opus: return "Opus"
        }
    }
}

/// 画面の文字の大きさ。標準を最小にして、大きめに切り替えられる
enum TextSize: String {
    case standard, large

    var toggled: TextSize { self == .standard ? .large : .standard }

    var typography: Typography { self == .standard ? .standard : .large }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var model: ModelChoice {
        get { ModelChoice(rawValue: defaults.string(forKey: "model") ?? "") ?? .haiku }
        set { defaults.set(newValue.rawValue, forKey: "model") }
    }

    static var bubbleVisible: Bool {
        get { defaults.object(forKey: "bubbleVisible") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "bubbleVisible") }
    }

    static var bubbleOrigin: NSPoint? {
        get {
            guard let s = defaults.string(forKey: "bubbleOrigin") else { return nil }
            return NSPointFromString(s)
        }
        set {
            if let p = newValue {
                defaults.set(NSStringFromPoint(p), forKey: "bubbleOrigin")
            } else {
                defaults.removeObject(forKey: "bubbleOrigin")
            }
        }
    }

    static var textSize: TextSize {
        get { TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: "textSize") }
    }

    /// チャット窓の大きさ。動かしていなければ nil（既定の大きさ）
    static var panelSize: NSSize? {
        get {
            guard let s = defaults.string(forKey: "panelSize") else { return nil }
            return NSSizeFromString(s)
        }
        set {
            if let size = newValue {
                defaults.set(NSStringFromSize(size), forKey: "panelSize")
            } else {
                defaults.removeObject(forKey: "panelSize")
            }
        }
    }

    /// claude の場所を手で決めたいときだけ使う（defaults write <バンドルID> claudePath /path/to/claude）
    static var claudePath: String? { defaults.string(forKey: "claudePath") }
}

enum AppPaths {
    /// claude を起動する作業フォルダ。プロジェクトの設定を拾わないよう、専用の場所にする。
    static var workDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Brand.appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
