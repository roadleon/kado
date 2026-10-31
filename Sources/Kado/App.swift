import AppKit
import Carbon
import ServiceManagement

@main
enum KadoMain {
    static func main() {
        // 終わった claude に書き込んでも落ちないようにする
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ChatStore()
    private var bubble: BubbleWindow!
    private var panel: ChatPanel!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var idleTimer: Timer?
    private var captureProcess: Process?
    private var isCapturing = false
    /// 起動の途中で届いた URL。準備ができてから処理する
    private var pendingURLs: [URL] = []
    private var isReady = false
    /// 窓を開く前に使っていたアプリ。閉じたらそこへ戻す。
    private var previousApp: NSRunningApplication?

    /// 使わないまま、この時間が過ぎたら claude を止める
    private let idleLimit: TimeInterval = 30 * 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        if quitIfAlreadyRunning() { return }

        buildMainMenu()

        bubble = BubbleWindow(
            onClick: { [weak self] in self?.toggleChat() },
            onMoved: { [weak self] in self?.bubbleMoved() },
            onRightClick: { [weak self] event, view in self?.showBubbleMenu(event, in: view) }
        )
        bubble.placeAtSavedPosition()
        if Settings.bubbleVisible { bubble.orderFrontRegardless() }

        panel = ChatPanel(store: store, onClose: { [weak self] in self?.hideChat() })
        store.captureHandler = { [weak self] in self?.captureImage() }

        setUpStatusItem()

        hotKey = HotKey(keyCode: kVK_ANSI_M, modifiers: controlKey | optionKey) { [weak self] in
            self?.toggleChat()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bubble.placeAtSavedPosition() }
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.isVisible else { return }
                self.store.releaseIfIdle(olderThan: self.idleLimit)
            }
        }

        isReady = true
        handle(urls: pendingURLs)
        pendingURLs = []
    }

    func applicationWillTerminate(_ notification: Notification) {
        if captureProcess?.isRunning == true { captureProcess?.terminate() }
        store.shutdown()
    }

    /// 起動中にもう一度開かれたら（Spotlight や Finder から）、バブルを戻してチャットを開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !Settings.bubbleVisible {
            Settings.bubbleVisible = true
            bubble.placeAtSavedPosition()
            bubble.orderFrontRegardless()
        }
        if !panel.isVisible { showChat() }
        return false
    }

    /// 外から操作する（Raycast やショートカット.app 用）
    /// <スキーム>://toggle・open・close・new、<スキーム>://ask?q=質問（スキームは Brand.urlScheme）
    func application(_ application: NSApplication, open urls: [URL]) {
        if isReady {
            handle(urls: urls)
        } else {
            pendingURLs += urls
        }
    }

    private func handle(urls: [URL]) {
        for url in urls where url.scheme == Brand.urlScheme {
            switch url.host {
            case "open": if !panel.isVisible { showChat() }
            case "close": hideChat()
            case "new": newConversation()
            case "ask":
                let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let question = items.first { $0.name == "q" }?.value ?? ""
                if !panel.isVisible { showChat() }
                // ウェブページなどから勝手に送られないよう、入力欄に入れるだけにする
                store.fillDraft(question)
                // 動作確認用：open --env KADO_AUTOSEND=1 で起動したときだけ、image= の画像を添付して送信まで行う
                if ProcessInfo.processInfo.environment["KADO_AUTOSEND"] == "1" {
                    if let path = items.first(where: { $0.name == "image" })?.value {
                        store.attach(urls: [URL(fileURLWithPath: path)]) { [weak self] in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.store.send() }
                        }
                    } else {
                        store.send()
                    }
                }
            default: toggleChat()
            }
        }
    }

    // MARK: - 開閉

    @objc func toggleChat() {
        if panel.isVisible {
            hideChat()
        } else {
            showChat()
        }
    }

    func showChat() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        panel.position(near: bubble.isVisible ? bubble.frame : nil)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        bubble.state.isOpen = true
        store.prepare()
    }

    @objc func hideChat() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        bubble.state.isOpen = false
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }
        previousApp = nil
    }

    private func bubbleMoved() {
        bubble.settleAndSave()
        if panel.isVisible {
            panel.position(near: bubble.frame)
        }
    }

    /// 撮影中だけチャットを隠し、範囲選択の終了を非同期で待つ。
    private func captureImage() {
        guard !isCapturing else { return }
        isCapturing = true
        hideChat()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kado-capture-\(UUID().uuidString).png")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", url.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finishCapture(at: url) }
                }
            }
            self.captureProcess = process
            do {
                try process.run()
            } catch {
                self.finishCapture(at: url)
            }
        }
    }

    private func finishCapture(at url: URL) {
        captureProcess = nil
        isCapturing = false
        if FileManager.default.fileExists(atPath: url.path) {
            store.attach(urls: [url]) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        showChat()
    }

    // MARK: - メニューバー

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: Brand.symbol, accessibilityDescription: Brand.displayName)
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu == statusItem.menu else { return }
        fillMenu(menu)
    }

    /// メニューバーのアイコンは切り欠きに隠れることがあるので、バブルの右クリックでも同じメニューを出す
    private func showBubbleMenu(_ event: NSEvent, in view: NSView) {
        let menu = NSMenu()
        fillMenu(menu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func fillMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = NSMenuItem(
            title: panel.isVisible ? L10n.t("閉じる", "Close") : L10n.t("開く", "Open"),
            action: #selector(toggleChat),
            keyEquivalent: "m"
        )
        toggle.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(toggle)
        menu.addItem(NSMenuItem(title: L10n.t("新しい会話", "New Chat"), action: #selector(newConversation), keyEquivalent: ""))
        menu.addItem(.separator())

        let modelItem = NSMenuItem(title: L10n.t("モデル", "Model"), action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for choice in ModelChoice.allCases {
            let item = NSMenuItem(title: choice.label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.representedObject = choice.rawValue
            item.state = choice == store.model ? .on : .off
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let bubbleItem = NSMenuItem(title: L10n.t("バブルを表示", "Show Bubble"), action: #selector(toggleBubble), keyEquivalent: "")
        bubbleItem.state = Settings.bubbleVisible ? .on : .off
        menu.addItem(bubbleItem)
        menu.addItem(NSMenuItem(title: L10n.t("バブルを右下に戻す", "Reset Bubble Position"), action: #selector(resetBubble), keyEquivalent: ""))
        if Settings.panelSize != nil {
            menu.addItem(NSMenuItem(title: L10n.t("チャット窓を元の大きさに戻す", "Reset Chat Window Size"), action: #selector(resetPanelSize), keyEquivalent: ""))
        }

        let loginItem = NSMenuItem(title: L10n.t("ログイン時に起動", "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.t("\(Brand.displayName)を終了", "Quit \(Brand.displayName)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        for item in modelMenu.items {
            item.target = self
        }
    }

    @objc private func newConversation() {
        store.newConversation()
        if !panel.isVisible { showChat() }
    }

    @objc private func resetPanelSize() {
        Settings.panelSize = nil
        if panel.isVisible { panel.position(near: bubble.isVisible ? bubble.frame : nil) }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ModelChoice(rawValue: raw) else { return }
        store.setModel(choice)
    }

    @objc private func toggleBubble() {
        Settings.bubbleVisible.toggle()
        if Settings.bubbleVisible {
            bubble.placeAtSavedPosition()
            bubble.orderFrontRegardless()
        } else {
            bubble.orderOut(nil)
        }
    }

    @objc private func resetBubble() {
        Settings.bubbleOrigin = nil
        bubble.placeAtDefaultPosition()
        Settings.bubbleOrigin = bubble.frame.origin
        if !Settings.bubbleVisible {
            Settings.bubbleVisible = true
            bubble.orderFrontRegardless()
        }
        if panel.isVisible { panel.position(near: bubble.frame) }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.t("ログイン時の起動を切り替えられませんでした", "Couldn’t change launch at login")
            alert.informativeText = L10n.t("\(error.localizedDescription)\n\nシステム設定 > 一般 > ログイン項目 から設定できます。", "\(error.localizedDescription)\n\nYou can change this in System Settings > General > Login Items.")
            alert.runModal()
        }
    }

    // MARK: - 準備

    /// 表に出ないアプリでもコピー・貼り付けなどのショートカットが効くよう、メインメニューを用意する
    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: L10n.t("\(Brand.displayName)を終了", "Quit \(Brand.displayName)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.t("ファイル", "File"))
        let newItem = NSMenuItem(title: L10n.t("新しい会話", "New Chat"), action: #selector(newConversation), keyEquivalent: "n")
        newItem.target = self
        fileMenu.addItem(newItem)
        let closeItem = NSMenuItem(title: L10n.t("閉じる", "Close"), action: #selector(hideChat), keyEquivalent: "w")
        closeItem.target = self
        fileMenu.addItem(closeItem)
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.t("編集", "Edit"))
        editMenu.addItem(NSMenuItem(title: L10n.t("取り消す", "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L10n.t("やり直す", "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: L10n.t("カット", "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L10n.t("コピー", "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L10n.t("ペースト", "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L10n.t("すべてを選択", "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    /// 2つ目を起動したら、先に動いている方を残して終わる
    private func quitIfAlreadyRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine }
        guard !others.isEmpty else { return false }
        NSApp.terminate(nil)
        return true
    }
}
