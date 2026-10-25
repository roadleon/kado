import AppKit
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    var isError = false
    var isDone = false
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isResponding = false
    /// 回答中に裏でしていること（「ウェブを検索しています」など）。文字が届き始めたら消す
    @Published private(set) var activity: String?
    @Published private(set) var model: ModelChoice = Settings.model
    @Published var draft = ""
    /// 値が変わるたびに入力欄へフォーカスを移す
    @Published private(set) var focusTick = 0
    /// 値が変わるたびに入力欄を空にする（日本語の変換中の文字も消す）
    @Published private(set) var clearTick = 0

    private var session: ClaudeSession?
    private var streamedThisTurn = false
    /// 止めた回の数。その回の result が届くまで、出力を捨てる
    private var pendingDiscards = 0
    private(set) var lastActivity = Date()

    // MARK: - 操作

    /// 窓を開いたときに呼ぶ。次の質問に備えて claude を起動しておく。
    func prepare() {
        focusTick += 1
        if session?.isRunning != true {
            startSession()
        }
    }

    /// 入力欄に文字を入れる（外からの呼び出し用。送信はしない）
    func fillDraft(_ text: String) {
        draft = text
        clearTick += 1
        focusTick += 1
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        draft = ""
        lastActivity = Date()

        messages.append(ChatMessage(role: .user, text: text, isDone: true))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true
        streamedThisTurn = false

        if session?.isRunning != true, let failure = startSession() {
            finishLast(with: failure, isError: true)
            return
        }
        guard let session else { return }
        do {
            try session.send(text)
        } catch {
            finishLast(with: L10n.t("Claude Code に質問を渡せませんでした。もう一度送ってみてください。", "Couldn’t send your question to Claude Code. Please try again."), isError: true)
            dropSession()
        }
    }

    func stop() {
        guard isResponding else { return }
        session?.interrupt()
        pendingDiscards += 1
        let current = messages.last?.text ?? ""
        finishLast(with: current.isEmpty ? L10n.t("（止めました）", "(Stopped)") : current, isError: false)
    }

    func newConversation() {
        dropSession()
        messages = []
        draft = ""
        clearTick += 1
        isResponding = false
        startSession()
        focusTick += 1
    }

    func setModel(_ choice: ModelChoice) {
        guard choice != model else { return }
        model = choice
        Settings.model = choice
        newConversation()
    }

    /// しばらく使っていないとき、claude を止めてメモリを空ける
    func releaseIfIdle(olderThan interval: TimeInterval) {
        guard !isResponding, session != nil, Date().timeIntervalSince(lastActivity) > interval else { return }
        dropSession()
        messages = []
    }

    func shutdown() {
        dropSession()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - claude とのやりとり

    /// 起動できなければ、その理由を返す
    @discardableResult
    private func startSession() -> String? {
        let session = ClaudeSession(model: model)
        session.onEvent = { [weak self] event in self?.handle(event) }
        do {
            try session.start()
            self.session = session
            return nil
        } catch {
            self.session = nil
            return error.localizedDescription
        }
    }

    private func dropSession() {
        session?.shutdown()
        session = nil
        pendingDiscards = 0
    }

    private func handle(_ event: ClaudeEvent) {
        switch event {
        case .textDelta(let text):
            guard pendingDiscards == 0, isResponding, let i = lastAssistantIndex else { return }
            messages[i].text += text
            streamedThisTurn = true
            activity = nil
            lastActivity = Date()

        case .textBlockStarted:
            // 検索の前に一言あったときは、本文と段落を分ける
            guard pendingDiscards == 0, isResponding, let i = lastAssistantIndex,
                  !messages[i].text.isEmpty, !messages[i].text.hasSuffix("\n\n")
            else { return }
            messages[i].text += "\n\n"

        case .toolStarted(let name):
            guard pendingDiscards == 0, isResponding else { return }
            switch name {
            case "WebSearch", "web_search": activity = L10n.t("ウェブを検索しています", "Searching the web")
            case "WebFetch", "web_fetch": activity = L10n.t("ページを読んでいます", "Reading the page")
            default: activity = L10n.t("調べています", "Researching")
            }
            lastActivity = Date()

        case .turnFinished(let resultText, let isError):
            if pendingDiscards > 0 {
                pendingDiscards -= 1
                return
            }
            guard isResponding else { return }
            if isError {
                let raw = resultText ?? ""
                finishLast(with: Self.friendlyError(raw), isError: true)
                // ログイン切れなどは、作り直さないと直らない
                if Self.isAuthError(raw) { dropSession() }
            } else if !streamedThisTurn, let resultText {
                finishLast(with: resultText, isError: false)
            } else {
                finishLast(with: nil, isError: false)
            }

        case .processEnded(let stderrTail):
            session = nil
            pendingDiscards = 0
            guard isResponding else { return }
            let hint = Self.isAuthError(stderrTail)
                ? Self.friendlyError(stderrTail)
                : L10n.t("Claude Code が途中で止まりました。もう一度聞くと、新しい会話として答えます。", "Claude Code stopped unexpectedly. Ask again to start a new chat.")
            finishLast(with: hint, isError: true)
        }
    }

    private var lastAssistantIndex: Int? {
        messages.lastIndex { $0.role == .assistant }
    }

    private func finishLast(with text: String?, isError: Bool) {
        if let i = lastAssistantIndex, !messages[i].isDone {
            if let text { messages[i].text = text }
            messages[i].isError = isError
            messages[i].isDone = true
        }
        isResponding = false
        activity = nil
    }

    private static func isAuthError(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["authenticate", "oauth", "log in", "login", "not logged"].contains { lower.contains($0) }
    }

    private static func friendlyError(_ raw: String) -> String {
        if isAuthError(raw) {
            return L10n.t("Claude Code にログインできていません。ターミナルで `claude auth login` を実行してから、もう一度聞いてください。", "You’re not logged in to Claude Code. Run `claude auth login` in Terminal, then ask again.")
        }
        if raw.lowercased().contains("limit") {
            return L10n.t("Claude の利用枠の上限に達したようです。\n\(raw)", "You may have reached your Claude usage limit.\n\(raw)")
        }
        return raw.isEmpty ? L10n.t("うまく答えられませんでした。もう一度聞いてみてください。", "Couldn’t answer your question. Please try again.") : raw
    }
}
