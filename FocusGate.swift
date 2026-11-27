import Cocoa

// Browsers to watch. Add your own bundle ID if yours isn't here
// (find it with: osascript -e 'id of app "Your Browser"').
let browserIDs: Set<String> = [
    "com.apple.Safari", "com.apple.SafariTechnologyPreview",
    "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium",
    "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
    "company.thebrowser.Browser", "com.operasoftware.Opera",
    "com.vivaldi.Vivaldi", "app.zen-browser.zen",
]
let thresholdSeconds = 10  // 5 minutes

// Window that can take focus without a title bar close button, and ignores Esc.
final class PromptWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) {}  // swallow Esc
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    var window: PromptWindow?
    var taskField = NSTextField()
    var stepField = NSTextField()
    var submit = NSButton()
    var browserSeconds = 0
    var prompting = false
    var statusItem: NSStatusItem!
    var enabled = true
    var pausedUntil: Date?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no Dock icon
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateMenu()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Reset the streak if the screen sleeps or the session locks.
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.browserSeconds = 0
            }
        }
    }

    func tick() {
        if prompting {
            // Keep the prompt in front until it's completed.
            if let w = window, !w.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKeyAndOrderFront(nil)
            }
            return
        }
        if let p = pausedUntil {
            if Date() >= p { pausedUntil = nil; updateMenu() }
            else { browserSeconds = 0; return }
        }
        if !enabled { browserSeconds = 0; return }
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              browserIDs.contains(id) else {
            browserSeconds = 0
            return
        }
        browserSeconds += 1
        if browserSeconds >= thresholdSeconds { showPrompt() }
    }

    func updateMenu() {
        let active = enabled && pausedUntil == nil
        statusItem.button?.title = active ? "🎯" : "💤"

        let m = NSMenu()
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = enabled ? .on : .off
        m.addItem(toggle)

        if let p = pausedUntil {
            let f = DateFormatter(); f.timeStyle = .short
            m.addItem(withTitle: "Paused until \(f.string(from: p))", action: nil, keyEquivalent: "")
            let r = NSMenuItem(title: "Resume now", action: #selector(resume), keyEquivalent: "")
            r.target = self
            m.addItem(r)
        } else {
            for (title, mins) in [("Pause 30 minutes", 30), ("Pause 1 hour", 60), ("Pause 2 hours", 120)] {
                let i = NSMenuItem(title: title, action: #selector(pause(_:)), keyEquivalent: "")
                i.target = self
                i.tag = mins
                m.addItem(i)
            }
        }
        m.addItem(.separator())
        m.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m
    }

    @objc func toggleEnabled() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "enabled")
        browserSeconds = 0
        updateMenu()
    }

    @objc func pause(_ sender: NSMenuItem) {
        pausedUntil = Date().addingTimeInterval(Double(sender.tag) * 60)
        browserSeconds = 0
        updateMenu()
    }

    @objc func resume() {
        pausedUntil = nil
        browserSeconds = 0
        updateMenu()
    }

    func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 13)
        return l
    }

    func showPrompt() {
        prompting = true
        taskField = NSTextField()
        stepField = NSTextField()
        taskField.placeholderString = "e.g. Draft the Q4 report"
        stepField.placeholderString = "e.g. Open the doc and write the outline"
        [taskField, stepField].forEach {
            $0.delegate = self
            $0.widthAnchor.constraint(equalToConstant: 400).isActive = true
        }

        submit = NSButton(title: "Start working", target: self, action: #selector(done))
        submit.keyEquivalent = "\r"
        submit.bezelStyle = .rounded
        submit.isEnabled = false

        let title = NSTextField(labelWithString: "You've been in the browser for 5 minutes.")
        title.font = .systemFont(ofSize: 16, weight: .semibold)

        let stack = NSStackView(views: [
            title,
            label("What task will you work on next?"), taskField,
            label("What is your very next step?"), stepField,
            submit,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)

        let w = PromptWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 260),
                             styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Refocus"
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        window = w

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(taskField)
    }

    func controlTextDidChange(_ obj: Notification) {
        submit.isEnabled = !trimmed(taskField).isEmpty && !trimmed(stepField).isEmpty
    }

    func trimmed(_ f: NSTextField) -> String {
        f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc func done() {
        let task = trimmed(taskField), step = trimmed(stepField)
        guard !task.isEmpty, !step.isEmpty else { return }
        log(task: task, step: step)
        window?.orderOut(nil)
        window = nil
        prompting = false
        browserSeconds = 0
    }

    func log(task: String, step: String) {
        let path = NSHomeDirectory() + "/focus-log.txt"
        let line = "\(ISO8601DateFormatter().string(from: Date()))\ttask: \(task)\tnext: \(step)\n"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            h.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
