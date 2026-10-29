import Foundation

enum ClaudeEvent {
    /// 回答の文字が少し届いた
    case textDelta(String)
    /// 新しい文のまとまりが始まった（検索のあとの本文など）
    case textBlockStarted
    /// 道具を使い始めた（WebSearch・WebFetch）
    case toolStarted(name: String)
    /// 1回の受け答えが終わった。resultText は最終的な回答（またはエラー文）
    case turnFinished(resultText: String?, isError: Bool)
    /// claude のプロセスが終わった（stderr の末尾つき）
    case processEnded(stderrTail: String)
}

enum KadoError: LocalizedError {
    case claudeNotFound
    case notRunning

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return L10n.t("Claude Code（claude コマンド）が見つかりません。ターミナルで `claude --version` が動くか確かめてください。", "Claude Code (the claude command) wasn’t found. Check that `claude --version` works in Terminal.")
        case .notRunning:
            return L10n.t("Claude Code が起動していません。", "Claude Code isn’t running.")
        }
    }
}

/// 手元の Claude Code を1本起動したままにして、stream-json で会話する。
@MainActor
final class ClaudeSession {
    var onEvent: (@MainActor (ClaudeEvent) -> Void)?

    private let model: ModelChoice
    private var process: Process?
    private var stdin: FileHandle?
    private var stdoutBuffer = Data()
    private var stderrTail = ""
    /// 書き込みが詰まっても画面が固まらないよう、別の列で書く
    private let writeQueue = DispatchQueue(label: "kado.stdin")
    /// 終了の知らせは、プロセスの終了と出力の読み終わりがそろってから出す
    private var processExited = false
    private var stdoutClosed = false
    private var stderrClosed = false

    init(model: ModelChoice) {
        self.model = model
    }

    var isRunning: Bool { process?.isRunning ?? false }

    func start() throws {
        let executable = try ClaudeLocator.find()
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model", model.cliName,
            "--effort", model.effort,
            // 調べ物のために、ウェブ検索とページの読み込みだけを使う。ファイル操作やコマンドは使わない
            "--tools", "WebSearch,WebFetch",
            "--allowedTools", "WebSearch", "WebFetch",
            "--strict-mcp-config",
            "--safe-mode",
            "--no-session-persistence",
            "--system-prompt", Self.systemPrompt(),
        ]
        process.currentDirectoryURL = AppPaths.workDir
        process.environment = Self.cleanEnvironment()

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if data.isEmpty {
                        self.stdoutClosed = true
                        self.reportEndIfFinished()
                    } else {
                        self.consume(data)
                    }
                }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if data.isEmpty {
                        self.stderrClosed = true
                        self.reportEndIfFinished()
                    } else {
                        self.stderrTail = String((self.stderrTail + text).suffix(2000))
                    }
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.processExited = true
                    self.reportEndIfFinished()
                }
            }
        }

        try process.run()
        self.process = process
        self.stdin = inPipe.fileHandleForWriting
    }

    func send(_ text: String, images: [ImageAttachment] = []) throws {
        let content: Any
        if images.isEmpty {
            content = text
        } else {
            var blocks: [[String: Any]] = images.map { image in
                ["type": "image", "source": [
                    "type": "base64", "media_type": image.mediaType, "data": image.base64,
                ]]
            }
            blocks.append(["type": "text", "text": text])
            content = blocks
        }
        try write([
            "type": "user",
            "message": ["role": "user", "content": content],
        ])
    }

    /// 回答の途中で止める
    func interrupt() {
        try? write([
            "type": "control_request",
            "request_id": UUID().uuidString,
            "request": ["subtype": "interrupt"],
        ])
    }

    func shutdown() {
        onEvent = nil
        if let stdin {
            writeQueue.async { try? stdin.close() }
        }
        stdin = nil
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            (process.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
                // 素直に終わらなければ、少し待ってから強制的に終わらせる
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        process = nil
    }

    // MARK: - 入出力

    private func write(_ object: [String: Any]) throws {
        guard let stdin, isRunning else { throw KadoError.notRunning }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        writeQueue.async {
            try? stdin.write(contentsOf: data)
        }
    }

    private func reportEndIfFinished() {
        guard processExited, stdoutClosed, stderrClosed else { return }
        flushRemainingLines()
        onEvent?(.processEnded(stderrTail: stderrTail))
        onEvent = nil
    }

    private func consume(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = stdoutBuffer[stdoutBuffer.startIndex..<newline]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            handleLine(Data(line))
        }
    }

    private func flushRemainingLines() {
        if !stdoutBuffer.isEmpty {
            let rest = stdoutBuffer
            stdoutBuffer.removeAll()
            handleLine(rest)
        }
    }

    private func handleLine(_ line: Data) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = object["type"] as? String
        else { return }

        switch type {
        case "stream_event":
            guard let event = object["event"] as? [String: Any] else { return }
            switch event["type"] as? String {
            case "content_block_start":
                guard let block = event["content_block"] as? [String: Any] else { return }
                switch block["type"] as? String {
                case "text":
                    onEvent?(.textBlockStarted)
                case "tool_use", "server_tool_use":
                    onEvent?(.toolStarted(name: block["name"] as? String ?? ""))
                default:
                    break
                }
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any],
                      delta["type"] as? String == "text_delta",
                      let text = delta["text"] as? String
                else { return }
                onEvent?(.textDelta(text))
            default:
                break
            }
        case "result":
            let isError = object["is_error"] as? Bool ?? false
            var text = object["result"] as? String
            // エラーのときは result が無く、errors に理由が入ることがある
            if text == nil, let errors = object["errors"] as? [Any], !errors.isEmpty {
                text = errors.map { "\($0)" }.joined(separator: "\n")
            }
            onEvent?(.turnFinished(resultText: text, isError: isError))
        default:
            break
        }
    }

    // MARK: - 起動の準備

    private static func systemPrompt() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isJapanese ? "ja_JP" : "en_US_POSIX")
        formatter.dateFormat = L10n.t("yyyy年M月d日（E）", "EEEE, MMMM d, yyyy")
        return """
        You are "\(Brand.displayName)", a small assistant that lives in the corner of the user's Mac screen and answers quick questions.
        - Reply in the same language the user writes in. Be concise and lead with the answer.
        - Questions may omit words or use abbreviations. Infer their meaning from the conversation and common usage. Ask a brief clarifying question only when the meaning is still ambiguous.
        - Use bullet points and code only when needed.
        - Do not use emoji.
        - For questions that need current information, fact-checking, or research, use WebSearch before answering. Use WebFetch to read pages when needed.
        - When you research an answer, end with 2–4 Markdown links to the pages you consulted. Use a heading in the user's language: "出典" for Japanese or "Sources" for English.
        - Write only the answer, without describing your research process (such as how you searched or whether you found outdated information).
        - You cannot read or write files or execute commands.
        Today's date: \(formatter.string(from: Date()))
        """
    }

    /// 呼び出し元（ターミナルや別の Claude Code）の環境変数を持ち込まない
    private static func cleanEnvironment() -> [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        var env: [String: String] = [
            "HOME": home,
            "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "ja_JP.UTF-8",
        ]
        for key in ["USER", "LOGNAME", "TMPDIR", "SHELL"] {
            if let value = inherited[key] { env[key] = value }
        }
        return env
    }
}

enum ClaudeLocator {
    static func find() throws -> URL {
        let fm = FileManager.default
        if let custom = Settings.claudePath, fm.isExecutableFile(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude",
        ]
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: hit)
        }
        if let path = lookUpWithLoginShell(), fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw KadoError.claudeNotFound
    }

    private static func lookUpWithLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        // シェルの設定が止まっても固まらないよう、3秒で打ち切る（出力は1行なので詰まらない）
        if finished.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
