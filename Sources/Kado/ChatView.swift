import SwiftUI

struct ChatView: View {
    @ObservedObject var store: ChatStore
    var onClose: () -> Void
    @State private var inputContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            messageList
            inputArea
        }
        .font(Theme.body)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
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
                .font(Theme.bodySmall)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 150)
    }

    // MARK: - 入力欄

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
                    focusTick: store.focusTick,
                    clearTick: store.clearTick,
                    onSubmit: { store.send() },
                    onEscape: onClose
                )
                .frame(height: inputHeight)
            }

            if store.isResponding {
                RoundButton(systemName: "stop.fill", enabled: true, help: L10n.t("止める", "Stop")) {
                    store.stop()
                }
            } else {
                RoundButton(systemName: "arrow.up", enabled: !trimmedDraft.isEmpty, help: L10n.t("送信（Enter）", "Send (Enter)")) {
                    store.send()
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
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .padding(.top, 4)
    }

    private var trimmedDraft: String {
        store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 折り返しを含めた行数に合わせて高くする（最大8行ほど。それを超えたら中でスクロール）
    private var inputHeight: CGFloat {
        min(max(inputContentHeight, 23), 140)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let activity: String?
    var onCopy: (String) -> Void
    @State private var copied = false

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .textSelection(.enabled)
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
                            .font(Theme.bodySmall)
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
                        .font(Theme.bodySmall)
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
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
