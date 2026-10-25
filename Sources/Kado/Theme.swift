import AppKit
import SwiftUI

/// 見た目の土台（色・文字・寸法）。画面ごとに値を持たず、ここから使う。
enum Theme {
    static let accentNS = Brand.accent
    static let accent = Color(nsColor: accentNS)

    static let body = Font.system(size: 13)
    static let bodySmall = Font.system(size: 11)
    static let heading = Font.system(size: 14, weight: .semibold)
    static let title = Font.system(size: 13, weight: .semibold)
    static let code = Font.system(size: 12, design: .monospaced)

    static let panelSize = NSSize(width: 380, height: 540)
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
