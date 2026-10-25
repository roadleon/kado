import AppKit
import SwiftUI

// MARK: - バブル（画面の端に浮かぶ丸ボタン）

final class BubbleState: ObservableObject {
    @Published var isOpen = false
}

struct BubbleView: View {
    @ObservedObject var state: BubbleState
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            Image(systemName: state.isOpen ? "xmark" : Brand.symbol)
                .font(.system(size: state.isOpen ? 16 : 21, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: Theme.bubbleDiameter, height: Theme.bubbleDiameter)
        .scaleEffect(hovering ? 1.06 : 1)
        .opacity(hovering || state.isOpen ? 1 : 0.88)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .animation(.easeOut(duration: 0.15), value: state.isOpen)
        .onHover { hovering = $0 }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// クリックとドラッグを見分けるための入れ物。描画は中の SwiftUI に任せる。
final class BubbleContainerView: NSView {
    var onClick: (() -> Void)?
    var onMoved: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var moved = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event, self)
    }

    override func mouseDown(with event: NSEvent) {
        // Control + クリックも右クリックとして扱う
        if event.modifierFlags.contains(.control) {
            dragStart = nil
            onRightClick?(event, self)
            return
        }
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.x
        let dy = now.y - dragStart.y
        if !moved, hypot(dx, dy) < 3 { return }
        moved = true
        window.setFrameOrigin(NSPoint(x: windowStart.x + dx, y: windowStart.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        if moved {
            onMoved?()
        } else {
            onClick?()
        }
        dragStart = nil
        windowStart = nil
    }
}

final class BubbleWindow: NSPanel {
    let state = BubbleState()

    init(
        onClick: @escaping () -> Void,
        onMoved: @escaping () -> Void,
        onRightClick: @escaping (NSEvent, NSView) -> Void
    ) {
        let side = Theme.bubbleDiameter + Theme.bubbleMargin * 2
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false

        let container = BubbleContainerView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        container.onClick = onClick
        container.onMoved = onMoved
        container.onRightClick = onRightClick
        let hosting = NSHostingView(rootView: BubbleView(state: state))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        contentView = container
    }

    override var canBecomeKey: Bool { false }

    /// 保存した位置に置く。画面の外なら右下に戻す。
    func placeAtSavedPosition() {
        if let saved = Settings.bubbleOrigin,
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: saved, size: frame.size)) }) {
            setFrameOrigin(clamped(saved, in: screen.visibleFrame))
        } else {
            placeAtDefaultPosition()
        }
    }

    func placeAtDefaultPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let inset = Theme.edgeInset - Theme.bubbleMargin
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - inset, y: visible.minY + inset))
    }

    /// ドラッグ後、画面からはみ出さないよう戻して位置を覚える
    func settleAndSave() {
        let screen = self.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            setFrameOrigin(clamped(frame.origin, in: visible))
        }
        Settings.bubbleOrigin = frame.origin
    }

    private func clamped(_ origin: NSPoint, in visible: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - frame.width),
            y: min(max(origin.y, visible.minY), visible.maxY - frame.height)
        )
    }
}

// MARK: - チャット窓

final class ChatPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(store: ChatStore, onClose: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Theme.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        onEscape = onClose

        let hosting = NSHostingView(rootView: ChatView(store: store, onClose: onClose))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: Theme.panelSize)
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    /// バブルのそばに開く。バブルが無いときは、マウスのある画面の右下に開く。
    func position(near bubble: NSRect?) {
        let size = Theme.panelSize
        if let bubble {
            let screen = NSScreen.screens.first { $0.frame.intersects(bubble) } ?? NSScreen.main
            guard let visible = screen?.visibleFrame else { return }
            let inner = bubble.insetBy(dx: Theme.bubbleMargin, dy: Theme.bubbleMargin)
            var x = inner.maxX - size.width
            var y = inner.maxY + Theme.gap
            if y + size.height > visible.maxY {
                // 上に入らなければ下に開く
                y = inner.minY - Theme.gap - size.height
            }
            if y < visible.minY {
                // 上下どちらも入らなければ横に開く
                y = visible.minY
                x = inner.minX - Theme.gap - size.width
                if x < visible.minX { x = inner.maxX + Theme.gap }
            }
            x = min(max(x, visible.minX), visible.maxX - size.width)
            y = min(max(y, visible.minY), visible.maxY - size.height)
            setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        } else {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            guard let visible = screen?.visibleFrame else { return }
            setFrame(
                NSRect(
                    x: visible.maxX - size.width - Theme.edgeInset,
                    y: visible.minY + Theme.edgeInset,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
        }
    }
}
