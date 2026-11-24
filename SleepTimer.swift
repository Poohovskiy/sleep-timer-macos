import Cocoa

// Плаваюча панель без рамки, яка приймає кліки
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// Плоска кнопка з м'яким підсвічуванням при наведенні
final class PillButton: NSButton {
    private var filled = true
    private var hovering = false
    private var pressed = false
    private var area: NSTrackingArea?

    override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.35 }
    }

    func configure(title: String, size: CGFloat, weight: NSFont.Weight,
                   color: NSColor, filled: Bool, height: CGFloat) {
        self.filled = filled
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
        heightAnchor.constraint(equalToConstant: height).isActive = true
        refreshBackground()
    }

    private func refreshBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            var a: CGFloat = 0
            if filled {
                a = pressed ? 0.24 : (hovering ? 0.15 : 0.07)
            } else if isEnabled {
                a = pressed ? 0.14 : (hovering ? 0.07 : 0)
            }
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(a).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBackground()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let a = area { removeTrackingArea(a) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        area = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; refreshBackground() }
    override func mouseExited(with event: NSEvent) { hovering = false; refreshBackground() }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refreshBackground()
        super.mouseDown(with: event)
        pressed = false
        refreshBackground()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let W: CGFloat = 252
    let H: CGFloat = 312

    var panel: FloatingPanel!
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    let timeLabel = NSTextField(labelWithString: "")
    let hintLabel = NSTextField(labelWithString: "")
    let cancelButton = PillButton(frame: .zero)
    let modeControl = NSSegmentedControl(labels: ["Пауза", "Закрити", "Сон Mac"],
                                         trackingMode: .selectOne, target: nil, action: nil)

    var timer: Timer?
    var endDate: Date?

    let hints = [
        "Потім: пауза відтворення",
        "Потім: закрити браузери і плеєри",
        "Потім: сон Mac"
    ]
    var mode = 0

    // Програми, які закриваються у режимі «Закрити»
    let bundleIDs = [
        "com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox",
        "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser",
        "com.spotify.client", "com.apple.Music", "com.apple.TV"
    ]

    // MARK: - Запуск

    func applicationDidFinishLaunching(_ notification: Notification) {
        mode = min(max(UserDefaults.standard.integer(forKey: "mode2"), 0), 2)
        buildUI()
        setupStatusItem()
        refreshIdle()
        showPanel()
    }

    // Клік по іконці в Dock знову показує віджет
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Рядок меню

    func setupStatusItem() {
        guard let b = statusItem.button else { return }
        b.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: "Таймер сну")
        b.imagePosition = .imageLeading
        b.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        b.target = self
        b.action = #selector(togglePanel)
    }

    func setMenuTitle(_ text: String) {
        statusItem.button?.title = text.isEmpty ? "" : " " + text
    }

    // MARK: - Інтерфейс

    func timeButton(_ minutes: Int) -> PillButton {
        let b = PillButton(frame: .zero)
        b.target = self
        b.action = #selector(startTimer(_:))
        b.tag = minutes * 60
        b.configure(title: "\(minutes) хв", size: 14, weight: .medium,
                    color: .labelColor, filled: true, height: 38)
        return b
    }

    func timeRow(_ minutes: [Int]) -> NSStackView {
        let s = NSStackView(views: minutes.map { timeButton($0) })
        s.orientation = .horizontal
        s.distribution = .fillEqually
        s.spacing = 8
        return s
    }

    func buildUI() {
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 100, y: 100, width: 900, height: 700)
        let frame = NSRect(x: vf.maxX - W - 24, y: vf.maxY - H - 24, width: W, height: H)

        panel = FloatingPanel(contentRect: frame,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let fx = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        fx.material = .popover
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 18
        fx.layer?.masksToBounds = true
        panel.contentView = fx

        // Заголовок і тонкий хрестик
        let title = NSTextField(labelWithString: "Таймер сну")
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Згорнути")
            ?? NSImage()
        let close = NSButton(image: xmark, target: self, action: #selector(collapsePanel))
        close.isBordered = false
        close.contentTintColor = .tertiaryLabelColor
        close.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let header = NSStackView(views: [title, close])
        header.orientation = .horizontal
        header.distribution = .fill

        // Великий час
        timeLabel.alignment = .center
        timeLabel.heightAnchor.constraint(equalToConstant: 52).isActive = true

        // Підпис під перемикачем режимів
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center

        // Режим
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.selectedSegment = mode
        modeControl.controlSize = .small
        modeControl.segmentDistribution = .fillEqually

        // Скасувати
        cancelButton.target = self
        cancelButton.action = #selector(cancelTimer)
        cancelButton.configure(title: "Скасувати таймер", size: 12, weight: .regular,
                               color: .secondaryLabelColor, filled: false, height: 26)
        cancelButton.isEnabled = false

        let row1 = timeRow([15, 25, 35])
        let row2 = timeRow([45, 60, 90])

        let stack = NSStackView(views: [header, timeLabel, row1, row2, modeControl, hintLabel, cancelButton])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .centerX
        stack.setCustomSpacing(8, after: header)
        stack.setCustomSpacing(16, after: timeLabel)
        stack.setCustomSpacing(14, after: row2)
        stack.setCustomSpacing(8, after: modeControl)
        stack.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: fx.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: fx.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: fx.trailingAnchor, constant: -18)
        ])
        for v in stack.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    // MARK: - Показ і згортання

    func showPanel() {
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc func collapsePanel() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.orderOut(nil)
            self?.panel.alphaValue = 1
        })
    }

    @objc func togglePanel() {
        if panel.isVisible {
            collapsePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Текст

    func showIdleText(_ text: String) {
        timeLabel.font = NSFont.systemFont(ofSize: 18, weight: .light)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.stringValue = text
    }

    func showCountdown(_ text: String) {
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .light)
        timeLabel.textColor = .labelColor
        timeLabel.stringValue = text
    }

    func refreshIdle() {
        showIdleText("Обери час")
        hintLabel.stringValue = hints[mode]
        cancelButton.isEnabled = false
        NSApp.dockTile.badgeLabel = nil
        setMenuTitle("")
    }

    // MARK: - Дії

    @objc func modeChanged() {
        mode = modeControl.selectedSegment
        UserDefaults.standard.set(mode, forKey: "mode2")
        hintLabel.stringValue = hints[mode]
    }

    @objc func startTimer(_ sender: NSButton) {
        timer?.invalidate()
        endDate = Date().addingTimeInterval(Double(sender.tag))
        cancelButton.isEnabled = true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
        collapsePanel()   // після вибору часу віджет згортається в рядок меню
    }

    @objc func cancelTimer() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        refreshIdle()
    }

    func tick() {
        guard let end = endDate else { return }
        let remaining = Int(ceil(end.timeIntervalSinceNow))
        if remaining <= 0 {
            finish()
            return
        }
        let text = String(format: "%d:%02d", remaining / 60, remaining % 60)
        showCountdown(text)
        hintLabel.stringValue = hints[mode]
        NSApp.dockTile.badgeLabel = "\((remaining + 59) / 60)"
        setMenuTitle(text)
    }

    func finish() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        refreshIdle()

        switch mode {
        case 1: quitPlayers()
        case 2: sleepMac()
        default: stopPlayback()
        }
    }

    // MARK: - Що робити по завершенню

    // Пауза (не перемикач): системна команда MediaRemote kMRPause.
    // Якщо її не вдалося завантажити, використовується медіаклавіша.
    func stopPlayback() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        if let handle = dlopen(path, RTLD_NOW), let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
            let send = unsafeBitCast(sym, to: SendCommand.self)
            _ = send(1, nil) // 1 = kMRPause
        } else {
            sendPlayPauseKey()
        }
    }

    func quitPlayers() {
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, bundleIDs.contains(id) {
                app.terminate()
            }
        }
    }

    func sleepMac() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]
        try? p.run()
    }

    // Запасний варіант: медіаклавіша Play/Pause (NX_KEYTYPE_PLAY = 16)
    func sendPlayPauseKey() {
        func post(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (16 << 16) | ((down ? 0xa : 0xb) << 8)
            let ev = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data1, data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
