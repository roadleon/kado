import AppKit
import SwiftUI

/// 入力欄。Enter で送信、Shift + Enter で改行。日本語の変換中は Enter で送信しない。
struct ChatInput: NSViewRepresentable {
    @Binding var text: String
    /// 折り返しを含めた、中身の高さ。入力欄の高さを決めるのに使う
    @Binding var contentHeight: CGFloat
    var focusTick: Int
    var clearTick: Int
    var onSubmit: () -> Void
    var onEscape: () -> Void
    var onAttachImages: ([NSImage]) -> Void
    var onAttachURLs: ([URL]) -> Void
    var onImageDragChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = Theme.accentNS
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 3)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.registerForDraggedTypes([.fileURL] + NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) })

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SubmitTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onEscape = onEscape
        textView.onPasteImages = onAttachImages
        textView.onPasteURLs = onAttachURLs
        textView.onImageDragChange = onImageDragChange
        textView.onLayoutChange = { [weak coordinator = context.coordinator, weak textView] in
            guard let textView else { return }
            coordinator?.measure(textView)
        }
        if context.coordinator.lastClearTick != clearTick {
            context.coordinator.lastClearTick = clearTick
            // 変換中の文字ごと消す
            textView.inputContext?.discardMarkedText()
            textView.unmarkText()
            textView.string = text
            textView.undoManager?.removeAllActions()
            context.coordinator.measure(textView)
        } else if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            context.coordinator.measure(textView)
        }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInput
        var lastFocusTick = -1
        var lastClearTick = 0

        init(_ parent: ChatInput) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            measure(textView)
        }

        func measure(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
            layoutManager.ensureLayout(for: container)
            let height = ceil(layoutManager.usedRect(for: container).height + textView.textContainerInset.height * 2)
            guard abs(height - parent.contentHeight) > 0.5 else { return }
            // 画面の更新中に値を変えないよう、次の周回で反映する
            DispatchQueue.main.async { [self] in
                parent.contentHeight = height
                textView.scrollRangeToVisible(textView.selectedRange())
            }
        }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onEscape: (() -> Void)?
    var onPasteImages: (([NSImage]) -> Void)?
    var onPasteURLs: (([URL]) -> Void)?
    var onImageDragChange: ((Bool) -> Void)?
    /// 折り返しが変わりうるとき（日本語の変換中や、幅が変わったとき）に呼ぶ
    var onLayoutChange: (() -> Void)?

    /// 文字専用の入力欄は、クリップボードに画像しかないと「ペースト」を押せない状態にする。
    /// ⌘V はこのメニュー項目を通るので、画像があるときは押せるようにする
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), hasImages(in: .general) { return true }
        return super.validateUserInterfaceItem(item)
    }

    /// 画像ファイル → 文字 → 画像の順に見る。表計算の表などは文字と画像の両方を持つので、文字を優先する
    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        let urls = ImageTransfer.imageURLs(in: pasteboard)
        if !urls.isEmpty {
            onPasteURLs?(urls)
        } else if pasteboard.string(forType: .string)?.isEmpty == false {
            super.paste(sender)
        } else if !attachImages(from: pasteboard) {
            super.paste(sender)
        }
    }

    private func hasImages(in pasteboard: NSPasteboard) -> Bool {
        !ImageTransfer.imageURLs(in: pasteboard).isEmpty
            || pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    private func attachImages(from pasteboard: NSPasteboard) -> Bool {
        let urls = ImageTransfer.imageURLs(in: pasteboard)
        if !urls.isEmpty {
            onPasteURLs?(urls)
            return true
        }
        let images = ImageTransfer.images(in: pasteboard)
        guard !images.isEmpty else { return false }
        onPasteImages?(images)
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImages(in: sender.draggingPasteboard) {
            onImageDragChange?(true)
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasImages(in: sender.draggingPasteboard) {
            onImageDragChange?(true)
            return .copy
        }
        onImageDragChange?(false)
        return super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onImageDragChange?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if hasImages(in: sender.draggingPasteboard) { return true }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onImageDragChange?(false)
        if attachImages(from: sender.draggingPasteboard) { return true }
        return super.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onImageDragChange?(false)
        super.concludeDragOperation(sender)
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onLayoutChange?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onLayoutChange?() }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isReturn, !hasMarkedText(), !modifiers.contains(.shift), !modifiers.contains(.option) {
            onSubmit?()
            return
        }
        if event.keyCode == 53, !hasMarkedText() {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
