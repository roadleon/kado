import AppKit
import SwiftUI

/// 見た目の土台（色・文字・寸法）。画面ごとに値を持たず、ここから使う。
enum Theme {
    static let accentNS = Brand.accent
    static let accent = Color(nsColor: accentNS)

    /// 見出しなど、窓の枠の文字。会話の文字は Typography で大きさを変える
    static let bodySmall = Font.system(size: 11)
    static let title = Font.system(size: 13, weight: .semibold)

    static let panelSize = NSSize(width: 380, height: 540)
    static let panelMinSize = NSSize(width: 320, height: 400)
    static let panelRadius: CGFloat = 14
    static let bubbleDiameter: CGFloat = 50
    /// バブルの影を描くための余白
    static let bubbleMargin: CGFloat = 8
    static let edgeInset: CGFloat = 16
    static let gap: CGFloat = 10

    static let hairline = Color.primary.opacity(0.08)
    static let codeBackground = Color.primary.opacity(0.06)
    static let userBubble = accent.opacity(0.16)
}

/// 会話の文字の大きさ一式。本文の大きさから、ほかの大きさを決める
struct Typography {
    let bodySize: CGFloat

    static let standard = Typography(bodySize: 13)
    static let large = Typography(bodySize: 15)

    var body: Font { .system(size: bodySize) }
    var bodySmall: Font { .system(size: bodySize - 2) }
    var heading: Font { .system(size: bodySize + 1, weight: .semibold) }
    var code: Font { .system(size: bodySize - 1, design: .monospaced) }
}

private struct TypographyKey: EnvironmentKey {
    static let defaultValue = Typography.standard
}

extension EnvironmentValues {
    var typography: Typography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }
}

/// 背景のすりガラス
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
