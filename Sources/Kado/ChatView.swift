import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @ObservedObject var store: ChatStore
    var onClose: () -> Void
    @State private var inputContentHeight: CGFloat = 0
    @State private var dropTargeted = false
    @State private var inputDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            messageList
            inputArea
        }
        .font(typography.body)
        .environment(\.typography, typography)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(dropTargeted || inputDropTargeted ? Theme.accent : Theme.hairline,
                              lineWidth: dropTargeted || inputDropTargeted ? 2 : 1)
                .allowsHitTesting(false)
        )
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $dropTargeted, perform: attachProviders)
    }

    // MARK: - 見出し

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 8, height: 8)
            Text(Brand.displayName)
                .font(Theme.title)
            Menu {
                ForEach(ModelChoice.allCases) { choice in
                    Button {
                        store.setModel(choice)
                    } label: {
                        if choice == store.model {
                            Label(choice.label, systemImage: "checkmark")
                        } else {
                            Text(choice.label)
                        }
                    }
                }
            } label: {
                Text(store.model.shortLabel)
                    .font(Theme.bodySmall)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .help(L10n.t("モデルを選ぶ（会話は新しくなります）", "Choose a model (starts a new chat)"))

            Spacer()

            IconButton(
                systemName: "textformat.size",
                help: store.textSize == .large
                    ? L10n.t("文字を標準の大きさに戻す", "Use standard text size")
                    : L10n.t("文字を大きくする", "Use larger text"),
                isOn: store.textSize == .large
            ) {
                store.toggleTextSize()
            }
            IconButton(systemName: "square.and.pencil", help: L10n.t("新しい会話（⌘N）", "New Chat (⌘N)")) {
                store.newConversation()
            }
            IconButton(systemName: "xmark", help: L10n.t("閉じる（Esc）", "Close (Esc)"), action: onClose)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    // MARK: - 会話

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if store.messages.isEmpty {
                        emptyState
                    }
                    ForEach(store.messages) { message in
                        let isLast = message.id == store.messages.last?.id
                        MessageRow(
                            message: message,
                            isStreaming: store.isResponding && isLast,
                            activity: isLast ? store.activity : nil,
                            onCopy: store.copy
                        )
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: store.messages.last?.text) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: store.messages.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: store.activity) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(L10n.t("ちょっとした質問をどうぞ", "What would you like to know?"))
                .foregroundStyle(.secondary)
            Text(L10n.t("Enter で送信　Shift + Enter で改行　⌃⌥M で開閉", "Enter to send · Shift + Enter for a new line · ⌃⌥M to toggle"))
                .font(typography.bodySmall)
                .foregroundStyle(.tertiary)
            Text(L10n.t("画像は ⌘V・ドラッグ・撮影ボタンで添付できます", "Attach images with ⌘V, drag and drop, or the capture button"))
                .font(typography.bodySmall)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 150)
    }

    // MARK: - 入力欄

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let notice = store.notice {
                Text(notice)
                    .font(typography.bodySmall)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                if !store.pendingImages.isEmpty {
                    pendingImageStrip
                }
                HStack(alignment: .bottom, spacing: 8) {
                    IconButton(systemName: "camera.viewfinder", help: L10n.t("画面の一部を撮って添付", "Capture part of the screen")) {
                        store.requestCapture()
                    }
                    ZStack(alignment: .topLeading) {
                        if store.draft.isEmpty {
                            Text(L10n.t("質問を入力", "Ask anything"))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 3)
                                .allowsHitTesting(false)
                        }
                        ChatInput(
                            text: $store.draft,
                            contentHeight: $inputContentHeight,
                            fontSize: typography.bodySize,
                            focusTick: store.focusTick,
                            clearTick: store.clearTick,
                            onSubmit: { store.send() },
                            onEscape: onClose,
                            onAttachImages: { store.attach(images: $0) },
                            onAttachURLs: { store.attach(urls: $0) },
                            onImageDragChange: { inputDropTargeted = $0 }
                        )
                        .frame(height: inputHeight)
                    }

                    if store.isResponding {
                        RoundButton(systemName: "stop.fill", enabled: true, help: L10n.t("止める", "Stop")) {
                            store.stop()
                        }
                    } else {
                        RoundButton(systemName: "arrow.up", enabled: !trimmedDraft.isEmpty || !store.pendingImages.isEmpty, help: L10n.t("送信（Enter）", "Send (Enter)")) {
                            store.send()
                        }
                    }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline)
                    .allowsHitTesting(false)
            )
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    private var pendingImageStrip: some View {
        HStack(spacing: 8) {
            ForEach(store.pendingImages) { image in
                Image(nsImage: image.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            store.removePendingImage(id: image.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(.black.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t("画像を外す", "Remove image"))
                        .accessibilityLabel(L10n.t("画像を外す", "Remove image"))
                    }
            }
        }
        .padding(.vertical, 2)
    }

    /// ファイル URL を優先し、同じ画像を二重に添付しない。
    private func attachProviders(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        for provider in supported {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                          ImageTransfer.isImageURL(url) else { return }
                    DispatchQueue.main.async { store.attach(urls: [url]) }
                }
            } else {
                let type = provider.registeredTypeIdentifiers.first {
                    UTType($0)?.conforms(to: .image) == true
                } ?? UTType.image.identifier
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                    DispatchQueue.main.async { store.attach(data: data ?? Data()) }
                }
            }
        }
        return !supported.isEmpty
    }

    private var trimmedDraft: String {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var typography: Typography { store.textSize.typography }

    /// 折り返しを含めた行数に合わせて高くする（最大8行ほど。それを超えたら中でスクロール）
    private var inputHeight: CGFloat {
        let size = typography.bodySize
        return min(max(inputContentHeight, size + 10), size / 13 * 140)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let activity: String?
    var onCopy: (String) -> Void
    @State private var copied = false
    @Environment(\.typography) private var typography

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 6) {
                    if !message.images.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(Array(message.images.enumerated()), id: \.offset) { _, image in
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 64, maxHeight: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                        }
                    }
                    if !message.text.isEmpty {
                        Text(message.text)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty && isStreaming {
                    ThinkingDots(label: activity)
                } else if message.isError {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Theme.accent)
                        Text(LocalizedStringKey(message.text))
                            .textSelection(.enabled)
                    }
                } else {
                    MarkdownView(text: message.text, onCopy: onCopy)
                        .textSelection(.enabled)
                    if isStreaming, let activity {
                        ThinkingDots(label: activity)
                    }
                }

                if message.isDone && !message.isError && !message.text.isEmpty {
                    Button {
                        onCopy(message.text)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label(copied ? L10n.t("コピーしました", "Copied") : L10n.t("回答をコピー", "Copy answer"), systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(typography.bodySmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 回答を待つあいだの3つの点。検索中などは、その説明を添える
private struct ThinkingDots: View {
    var label: String?
    @Environment(\.typography) private var typography

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(Theme.accent.opacity(i == step ? 0.9 : 0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                if let label {
                    Text(label)
                        .font(typography.bodySmall)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct IconButton: View {
    let systemName: String
    let help: String
    /// 切り替え式のボタンが入っているとき、アクセント色にする
    var isOn = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                // 日本語の環境では文字の記号が「ぁあ」に置き換わるので、英字の形に固定する
                .environment(\.locale, Locale(identifier: "en"))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct RoundButton: View {
    let systemName: String
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(enabled ? Theme.accent : Color.secondary.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }
}
