//
//  AetherGUI — a menu bar front end for the Aether client.
//  Click the bolt icon in the menu bar to connect, switch preset, or read the log.
//

import Cocoa
import AppKit

let kAetherDir = NSHomeDirectory() + "/bin/aether"
let kAetherBin = kAetherDir + "/aether"
let kDefaultBind = "127.0.0.1:1819"

// MARK: - persisted settings

struct Cfg {
    private static let d = UserDefaults.standard

    static var proto: String {
        get { d.string(forKey: "proto") ?? "masque" }
        set { d.set(newValue, forKey: "proto") }
    }
    static var transport: String { // h3 | h2
        get { d.string(forKey: "transport") ?? "h3" }
        set { d.set(newValue, forKey: "transport") }
    }
    static var scan: String {
        get { d.string(forKey: "scan") ?? "balanced" }
        set { d.set(newValue, forKey: "scan") }
    }
    static var noize: String {
        get { d.string(forKey: "noize") ?? "firewall" }
        set { d.set(newValue, forKey: "noize") }
    }
    static var peer: String {
        get { d.string(forKey: "peer") ?? "" }
        set { d.set(newValue, forKey: "peer") }
    }
    static var bind: String {
        get { d.string(forKey: "bind") ?? kDefaultBind }
        set { d.set(newValue, forKey: "bind") }
    }
    /// The host half of `bind` ("127.0.0.1" from "127.0.0.1:1819").
    static var host: String {
        bind.split(separator: ":", maxSplits: 1).first.map(String.init) ?? "127.0.0.1"
    }
    /// This app's pid, passed to the /bin/sh tunnel wrapper so it can tear the
    /// tunnel down if the GUI is force-quit or crashes. Captured once at launch;
    /// the GUI is a single long-lived process, so it never changes.
    static let watchPID: String = String(ProcessInfo.processInfo.processIdentifier)
    static var extra: String {
        get { d.string(forKey: "extra") ?? "" }
        set { d.set(newValue, forKey: "extra") }
    }
    static var stats: Bool {
        get { (d.object(forKey: "stats") as? Bool) ?? true }
        set { d.set(newValue, forKey: "stats") }
    }
    static var logInMenu: Bool {
        get { (d.object(forKey: "logInMenu") as? Bool) ?? false }
        set { d.set(newValue, forKey: "logInMenu") }
    }
    static var menuLogHeight: Int {
        get { (d.object(forKey: "menuLogHeight") as? Int) ?? 180 }
        set { d.set(newValue, forKey: "menuLogHeight") }
    }
    static var autoStart: Bool {
        get { (d.object(forKey: "autoStart") as? Bool) ?? true }
        set { d.set(newValue, forKey: "autoStart") }
    }
    static var loginItem: Bool {
        get { d.bool(forKey: "loginItem") }
        set { d.set(newValue, forKey: "loginItem") }
    }

    static var port: Int {
        Int(bind.split(separator: ":").last.map(String.init) ?? "1819") ?? 1819
    }
}

let kProtos: [(String, String)] = [
    ("masque", "MASQUE over WARP"),
    ("wg", "WireGuard"),
    ("gool", "Gool (WARP in WARP)"),
    ("mim", "MASQUE in MASQUE"),
]
let kScans: [(String, String)] = [
    ("turbo", "Turbo — first that answers"),
    ("balanced", "Balanced — default"),
    ("thorough", "Thorough — sweep ranges"),
    ("verified", "Verified — measured edges"),
    ("ironclad", "Ironclad — real traffic test"),
]
let kNoizes: [(String, String)] = [
    ("off", "Off"),
    ("light", "Light"),
    ("firewall", "Firewall"),
    ("balanced", "Balanced"),
    ("gfw", "GFW"),
    ("aggressive", "Aggressive"),
]

func tokenize(_ s: String) -> [String] {
    var out: [String] = []
    var cur = ""
    var inQuote = false
    var quoteChar: Character = "\""
    for ch in s {
        if inQuote {
            if ch == quoteChar { inQuote = false } else { cur.append(ch) }
        } else if ch == "\"" || ch == "'" {
            inQuote = true; quoteChar = ch
        } else if ch == " " || ch == "\t" || ch == "\n" {
            if !cur.isEmpty { out.append(cur); cur = "" }
        } else {
            cur.append(ch)
        }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

func buildArgs() -> [String] {
    var a: [String] = []
    switch Cfg.proto {
    case "wg": a += ["--wg"]
    case "gool": a += ["--gool"]
    case "mim": a += ["--mim"]
    default: a += ["--masque", Cfg.transport == "h2" ? "--h2" : "--h3"]
    }
    let p = Cfg.peer.trimmingCharacters(in: .whitespaces)
    if !p.isEmpty {
        switch Cfg.proto {
        case "gool": a += ["--wiw-outer", p]
        case "mim": a += ["--mim-outer", p]
        default: a += ["--peer", p]
        }
    }
    a += ["--scan", Cfg.scan]
    if Cfg.noize != "off" { a += ["--noize", Cfg.noize] }
    if Cfg.stats { a += ["--stats"] }
    a += ["--quick-reconnect"]
    if Cfg.bind != kDefaultBind { a += ["--bind", Cfg.bind] }
    a += tokenize(Cfg.extra)
    return a
}

// MARK: - app delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var statusItem: NSStatusItem!
    private var proc: Process?
    private var logLines: [String] = []
    private var logWindow: NSWindow?
    private var logView: NSTextView?
    private var connected = false
    private var exitIP = ""
    private var exitCC = ""
    private var everConnected = false

    // The log view that lives inside the status menu dropdown. Kept as a
    // property so appendLog() can push new lines into it without rebuilding
    // the whole menu (which would tear down the open menu).
    private var menuLogTV: NSTextView?
    private var menuLogScroll: NSScrollView?
    private var showLogInMenu = false
    private var menuLogDirty = false
    private var menuLogTick = 0

    // MARK: lifecycle

    /// The menu-bar glyph. Loaded from the bundle so the artwork can change
    /// without recompiling; falls back to an SF Symbol when absent.
    /// Marked as a template image so macOS tints it for dark/light menu bars
    /// and the active/pressed states.
    ///
    /// `size` is in POINTS, not pixels. The bundled PNG is 36px so that a
    /// Retina display (2x backing scale) gets native-resolution art — declaring
    /// 18x18 points against 36x36 pixels means the menu bar has to upscale
    /// nothing and the glyph stays sharp. An 18px bitmap here would be scaled
    /// up to fill a 36px slot, which is what made the icon look blurry.
    private func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon",
                                       withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !FileManager.default.fileExists(atPath: kAetherBin) {
            let alert = NSAlert()
            alert.messageText = "Aether binary not found"
            alert.informativeText = "Expected it at \(kAetherBin).\nPut the Aether folder there and relaunch this app."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let custom = menuBarImage() {
            custom.isTemplate = true
            statusItem.button?.image = custom
        } else if let img = NSImage(systemSymbolName: "bolt.shield.fill",
                                    accessibilityDescription: "Aether") {
            img.isTemplate = true
            statusItem.button?.image = img
        }
        statusItem.button?.toolTip = "Aether — click for options"
        rebuildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidEndTracking),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )

        if Cfg.loginItem { LoginItem.set(true) }
        if Cfg.autoStart { start() }
    }

    /// The dropdown closed. The view it hosted belongs to that menu and must
    /// not be written to afterwards, so drop the reference; the next open
    /// builds a fresh one.
    @objc private func menuDidEndTracking() {
        menuLogTV = nil
        menuLogScroll = nil
        showLogInMenu = false
        menuLogDirty = false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        stopTunnel()
        return .terminateNow
    }

    // MARK: menu

    /// True while an action from the menu is running. Until it is false we
    /// ignore any request to rebuild the menu, because AppKit tears the
    /// open menu down the moment its NSMenu object is replaced out from
    /// under it — picking a submenu item would dismiss the menu instead
    /// of confirming the choice, and the click would be lost.
    private var inMenuAction = false

    /// Rebuilds the status item menu from current settings. If a menu is
    /// currently open the swap is deferred to the next runloop pass so
    /// the menu stays alive while it is being used.
    @objc private func rebuildMenu() {
        guard !inMenuAction else { return }
        buildMenuNow()
    }

    /// Wraps an action that was invoked from the status menu so the menu
    /// can be rebuilt afterwards without tearing it down mid-interaction.
    /// NSMenu.validateMenuItem: runs on the same runloop turn, before any
    /// rebuild would happen, so assigning a fresh menu after the action
    /// returns is safe.
    private func menuAction(_ block: () -> Void) {
        inMenuAction = true
        block()
        inMenuAction = false
        buildMenuNow()
    }

    private func buildMenuNow() {
        let menu = NSMenu()

        let head = NSMenuItem()
        head.attributedTitle = statusLine()
        head.isEnabled = false
        menu.addItem(head)

        if !exitIP.isEmpty {
            let e = NSMenuItem()
            e.attributedTitle = NSAttributedString(
                string: "Exit: \(exitCC.isEmpty ? "?" : exitCC) · \(exitIP)",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                             .font: NSFont.menuFont(ofSize: 11)])
            e.isEnabled = false
            menu.addItem(e)
        }

        menu.addItem(.separator())

        if Cfg.logInMenu {
            let logItem = NSMenuItem()
            logItem.view = makeMenuLogView()
            menu.addItem(logItem)
            menu.addItem(.separator())
        }

        let toggle = NSMenuItem(
            title: connected ? "Disconnect" : (proc != nil ? "Stop…" : "Connect"),
            action: #selector(toggleTunnel),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let restart = NSMenuItem(title: "Restart tunnel",
                                 action: #selector(restartTunnel), keyEquivalent: "r")
        restart.target = self
        menu.addItem(restart)

        menu.addItem(.separator())

        addSub(menu, title: "Protocol", items: kProtos, current: Cfg.proto,
               action: #selector(setProto(_:)))
        if Cfg.proto == "masque" || Cfg.proto == "mim" {
            addSub(menu, title: "Transport",
                   items: [("h3", "HTTP/3 (QUIC)"), ("h2", "HTTP/2 (TCP)")],
                   current: Cfg.transport, action: #selector(setTransport(_:)))
        }
        addSub(menu, title: "Scan mode", items: kScans, current: Cfg.scan,
               action: #selector(setScan(_:)))
        addSub(menu, title: "Obfuscation", items: kNoizes, current: Cfg.noize,
               action: #selector(setNoize(_:)))

        menu.addItem(.separator())

        let copy = NSMenuItem(title: "Copy SOCKS5 address (\(Cfg.bind))",
                              action: #selector(copyBind), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)

        let sysOn = NSMenuItem(title: "Set system proxy (SOCKS5)",
                               action: #selector(setSystemProxy), keyEquivalent: "")
        sysOn.target = self
        sysOn.tag = 1
        menu.addItem(sysOn)

        let sysOff = NSMenuItem(title: "Clear system proxy",
                                action: #selector(setSystemProxy), keyEquivalent: "")
        sysOff.target = self
        sysOff.tag = 0
        menu.addItem(sysOff)

        menu.addItem(.separator())

        let log = NSMenuItem(title: "Show log", action: #selector(showLog),
                             keyEquivalent: "l")
        log.target = self
        menu.addItem(log)

        let inlineLog = NSMenuItem(title: "Show log inside menu",
                                   action: #selector(toggleLogInMenu),
                                   keyEquivalent: "")
        inlineLog.target = self
        inlineLog.state = Cfg.logInMenu ? .on : .off
        menu.addItem(inlineLog)

        let grow = NSMenuItem(title: "Larger log in menu",
                              action: #selector(growMenuLog), keyEquivalent: "")
        grow.target = self
        grow.isEnabled = Cfg.logInMenu
        menu.addItem(grow)

        let shrink = NSMenuItem(title: "Smaller log in menu",
                                action: #selector(shrinkMenuLog), keyEquivalent: "")
        shrink.target = self
        shrink.isEnabled = Cfg.logInMenu
        menu.addItem(shrink)

        let adv = NSMenuItem(title: "Advanced…", action: nil, keyEquivalent: ",")
        let advSub = NSMenu()
        for (title, sel) in [
            ("Gateway override…", #selector(editPeer)),
            ("SOCKS5 address…", #selector(editBind)),
            ("Extra flags…", #selector(editExtra)),
        ] as [(String, Selector)] {
            let m = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            m.target = self
            advSub.addItem(m)
        }
        menu.addItem(adv)
        menu.setSubmenu(advSub, for: adv)

        let login = NSMenuItem(title: "Start at login",
                               action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = Cfg.loginItem ? .on : .off
        login.isEnabled = Bundle.main.bundlePath.hasSuffix(".app")
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Aether", action: #selector(quitApp),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addSub(_ menu: NSMenu, title: String,
                        items: [(String, String)], current: String,
                        action: Selector) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (value, label) in items {
            let m = NSMenuItem(title: label, action: action, keyEquivalent: "")
            m.target = self
            m.representedObject = value
            m.state = (value == current) ? .on : .off
            sub.addItem(m)
        }
        menu.addItem(item)
        menu.setSubmenu(sub, for: item)
    }

    private func statusLine() -> NSAttributedString {
        let text: String
        let color: NSColor
        if connected {
            text = "Aether — connected"
            color = .systemGreen
        } else if proc != nil {
            text = "Aether — connecting…"
            color = .systemOrange
        } else {
            text = "Aether — stopped"
            color = .labelColor
        }
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: color,
        ])
    }

    // MARK: actions

    @objc private func toggleTunnel() {
        if proc != nil { stopTunnel() } else { start() }
        rebuildMenu()
    }

    @objc private func restartTunnel() {
        stopTunnel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.start()
        }
    }

    @objc private func setProto(_ sender: NSMenuItem) {
        menuAction {
            Cfg.proto = sender.representedObject as? String ?? "masque"
            if proc != nil { restartTunnel() }
        }
    }
    @objc private func setTransport(_ sender: NSMenuItem) {
        menuAction {
            Cfg.transport = sender.representedObject as? String ?? "h3"
            if proc != nil { restartTunnel() }
        }
    }
    @objc private func setScan(_ sender: NSMenuItem) {
        menuAction {
            Cfg.scan = sender.representedObject as? String ?? "balanced"
            if proc != nil { restartTunnel() }
        }
    }
    @objc private func setNoize(_ sender: NSMenuItem) {
        menuAction {
            Cfg.noize = sender.representedObject as? String ?? "firewall"
            if proc != nil { restartTunnel() }
        }
    }

    @objc private func copyBind() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("socks5://\(Cfg.bind)", forType: .string)
    }

    @objc private func toggleLogin() {
        menuAction { LoginItem.set(!Cfg.loginItem) }
    }

    // MARK: log inside the menu

    @objc private func toggleLogInMenu() {
        menuAction {
            Cfg.logInMenu.toggle()
            showLogInMenu = Cfg.logInMenu
        }
    }

    @objc private func growMenuLog() {
        menuAction {
            Cfg.menuLogHeight = min(Cfg.menuLogHeight + 60, 480)
            resizeMenuLog()
        }
    }

    @objc private func shrinkMenuLog() {
        menuAction {
            Cfg.menuLogHeight = max(Cfg.menuLogHeight - 60, 80)
            resizeMenuLog()
        }
    }

    private func resizeMenuLog() {
        guard let scroll = menuLogScroll else { return }
        let item = scroll.enclosingMenuItem
        var frame = scroll.frame
        frame.size.height = CGFloat(Cfg.menuLogHeight)
        scroll.frame = frame
        item?.view?.frame = NSRect(x: 0, y: 0, width: 420,
                                   height: CGFloat(Cfg.menuLogHeight))
        scroll.needsDisplay = true
    }

    /// Builds the read-only log view that is dropped into the status menu.
    /// Menu item views get no auto layout, so everything is sized here.
    private func makeMenuLogView() -> NSView {
        let width: CGFloat = 420
        let height = CGFloat(Cfg.menuLogHeight)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width,
                                                height: height))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        tv.textColor = .labelColor
        tv.insertionPointColor = .clear
        tv.textContainer?.containerSize = NSSize(width: width,
                                                 height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.textContainerInset = NSSize(width: 8, height: 6)
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        scroll.documentView = tv

        tv.string = logLines.suffix(200).joined(separator: "\n")
        tv.scrollToEndOfDocument(nil)

        menuLogTV = tv
        menuLogScroll = scroll
        showLogInMenu = true
        menuLogDirty = false

        return scroll
    }

    /// Called from appendLog. The view is inside the open menu, which AppKit
    /// owns; rewriting the whole string on every line causes visible flicker
    /// and jumps the scroll position. Lines are buffered and flushed once
    /// per runloop turn instead.
    private func scheduleMenuLogFlush() {
        menuLogDirty = true
        guard menuLogTick == 0 else { return }
        menuLogTick = 1
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.menuLogTick = 0
            guard self.menuLogDirty, let tv = self.menuLogTV else { return }
            self.menuLogDirty = false
            let wasAtBottom = self.menuLogScroll?.verticalScroller?.floatValue ?? 0
            tv.string = self.logLines.suffix(300).joined(separator: "\n")
            if wasAtBottom < 0.05 || wasAtBottom > 0.95 {
                tv.scrollToEndOfDocument(nil)
            }
        }
    }

    @objc private func quitApp() {
        stopTunnel()
        NSApp.terminate(nil)
    }

    // MARK: tunnel control

    func start() {
        guard proc == nil else { return }
        if let owner = portOwner() {
            // The most common cause is our own orphaned tunnel from a previous
            // session that was force-quit or crashed. Offer to clear that.
            if orphanPID != nil {
                offerToClearOrphan(owner: owner)
            } else {
                alert("Port \(Cfg.port) is already in use",
                      "Another program (\(owner)) is listening on \(Cfg.bind).\n"
                        + "Stop it, or change the SOCKS5 address in Advanced.")
            }
            return
        }
        let args = buildArgs()
        appendLog("» aether " + args.joined(separator: " "))

        let pipe = Pipe()

        // Keep the tunnel from outliving us. If this GUI is force-quit or
        // crashes, the normal terminate path never runs, so the tunnel
        // reparents to launchd (ppid 1) and keeps the SOCKS5 port bound —
        // blocking every later launch with "port already in use".
        //
        // A watchdog inside THIS process cannot help: it dies the instant the
        // GUI does. So we launch the tunnel through a tiny /bin/sh wrapper that
        // outlives us and kills the tunnel when it notices the GUI is gone.
        // The wrapper watches the GUI's pid ($$ is not available to us, so we
        // pass our own pid) and forwards SIGTERM/SIGINT to the child so a clean
        // quit still stops the tunnel promptly.
        let shim = Process()
        shim.executableURL = URL(fileURLWithPath: "/bin/sh")
        shim.currentDirectoryURL = URL(fileURLWithPath: kAetherDir)
        shim.environment = ProcessInfo.processInfo.environment
        shim.arguments = ["-c", """
            "$1" "${@:2}" &
            child=$!
            gui=\(Cfg.watchPID)
            trap 'kill -TERM $child 2>/dev/null' TERM INT
            while kill -0 "$gui" 2>/dev/null; do
              if ! kill -0 "$child" 2>/dev/null; then exit 0; fi
              sleep 0.5
            done
            # GUI is gone — take the tunnel down with it.
            kill -TERM "$child" 2>/dev/null
            sleep 1
            kill -KILL "$child" 2>/dev/null
            """,
            "sh", kAetherBin] + args
        // `sh -c 'script' name arg1 arg2...` puts "sh" in $0, the binary in $1.
        shim.standardOutput = pipe
        shim.standardError = pipe
        let shimHandle = pipe.fileHandleForReading
        shimHandle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.appendLog(text) }
        }
        // The Process we track for clean stop() is the shim; terminating it
        // trips its trap, which tears down the real tunnel.
        shim.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.proc = nil
                self?.connected = false
                self?.appendLog("■ tunnel process ended")
                self?.rebuildMenu()
            }
        }

        do {
            try shim.run()
            proc = shim
            connected = false
            rebuildMenu()
        } catch {
            appendLog("!! failed to start: \(error.localizedDescription)")
        }
    }

    func stopTunnel() {
        guard let p = proc else { return }
        appendLog("■ stopping…")
        p.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            if self?.proc === p, p.isRunning { p.interrupt() }
        }
    }

    /// Who is listening on our SOCKS5 port, if anyone. Returns nil when the
    /// port is free, otherwise the command name of the process holding it.
    ///
    /// Matches the exact `host:port` token (`127.0.0.1:1819`) rather than any
    /// line containing a colon — the old `out.contains(":")` matched the lsof
    /// header and the address column of unrelated entries, reporting the port
    /// as busy when it wasn't.
    private func portOwner() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-iTCP:\(Cfg.port)", "-sTCP:LISTEN"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let out = String(data: data, encoding: .utf8) else { return nil }

        let target = "\(Cfg.host):\(Cfg.port)"
        for line in out.split(separator: "\n") {
            guard line.contains(target) else { continue }
            // Skip the header row; a real entry's NAME field is the
            // host:port we matched.
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.first?.uppercased() == "COMMAND" { continue }
            if let cmd = cols.first { return String(cmd) }
        }
        return nil
    }

    /// Ask whether the orphaned-tunnel case applies and offer to clear it.
    /// A previous GUI that was force-quit or crashed leaves its `aether` child
    /// running (it reparents to launchd), so the port stays bound and every
    /// later launch is blocked. That leftover is safe to kill — it is not ours.
    private func offerToClearOrphan(owner: String) {
        let a = NSAlert()
        a.messageText = "Port \(Cfg.port) is already in use"
        a.informativeText = "A leftover Aether tunnel (\(owner), pid \(orphanPID ?? -1)) is still "
            + "holding \(Cfg.bind).\n\n"
            + "This happens when the app is force-quit or crashes and leaves its "
            + "tunnel running. Stop that leftover and start a fresh one?"
        a.addButton(withTitle: "Stop leftover & connect")
        a.addButton(withTitle: "Cancel")
        if a.runModal() != .alertFirstButtonReturn { return }

        killOrphan()
        // Give the socket time to release before binding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.start()
        }
    }

    /// Kill the orphaned tunnel process, if any.
    private func killOrphan() {
        guard let pid = orphanPID else { return }
        appendLog("» stopping leftover tunnel (pid \(pid))…")
        kill(pid, SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            // SIGTERM is polite; if it ignored that, force it.
            if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }

    /// The pid of any *foreign* `aether` process holding our port, i.e. one we
    /// did not spawn this session (our own child is `proc`). nil if none.
    private var orphanPID: Int32? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Ao", "pid,command"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        guard let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                              encoding: .utf8) else { return nil }
        let mine = proc?.processIdentifier
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.contains(kAetherBin) && !t.contains("AetherGUI") else { continue }
            let cols = t.split(separator: " ", omittingEmptySubsequences: true)
            guard let pidStr = cols.first, let pid = Int32(pidStr) else { continue }
            if pid == mine { continue }        // our own child, not an orphan
            return pid
        }
        return nil
    }

    // MARK: log handling

    private func appendLog(_ text: String) {
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            logLines.append(line)
            if logLines.count > 4000 { logLines.removeFirst(1000) }

            if line.contains("socks5 server listening") && !connected {
                connected = true
                everConnected = true
                NSSound(named: NSSound.Name("Glass"))?.play()
                rebuildMenu()
            }
            if line.contains("tunnel ended") || line.contains("tunnel failed") {
                connected = false
                rebuildMenu()
            }
            if let ip = parseExit(line) {
                exitIP = ip.ip
                exitCC = ip.cc
                rebuildMenu()
            }
        }
        if let tv = logView {
            let full = logLines.joined(separator: "\n")
            if tv.string != full {
                tv.string = full
                tv.scrollToEndOfDocument(nil)
            }
        }
        if showLogInMenu { scheduleMenuLogFlush() }
    }

    private func parseExit(_ line: String) -> (ip: String, cc: String)? {
        guard let range = line.range(of: "exit: ") else { return nil }
        let rest = String(line[range.upperBound...])
        let parts = rest.split(separator: ",", maxSplits: 2).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let ip = parts.first else { return nil }
        var cc = ""
        if parts.count > 1 { cc = String(parts[1].prefix(2)) }
        return (ip, cc)
    }

    // MARK: windows

    @objc private func showLog() {
        if let w = logWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 460),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "Aether log"
        w.center()
        // Keep a weak ref so closing the window does not leave a dangling
        // pointer that appendLog() would then write into.
        w.delegate = self
        w.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.borderType = .bezelBorder

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: scroll.bounds.width,
                                                 height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                            height: CGFloat.greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        scroll.documentView = tv
        w.contentView?.addSubview(scroll)

        tv.string = logLines.joined(separator: "\n")
        tv.scrollToEndOfDocument(nil)
        logView = tv
        logWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: advanced prompts

    /// A small modal sheet for one text value. Replaces the old Settings
    /// window: one question at a time, native alert look, no grid.
    private func prompt(title: String, message: String, value: String,
                        placeholder: String,
                        onSave: @escaping (String) -> Void) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")

        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        f.stringValue = value
        f.placeholderString = placeholder
        f.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        a.accessoryView = f
        a.window.initialFirstResponder = f

        // The status menu is not a window, so there is nothing to attach a
        // sheet to; run the alert modally over the frontmost app instead.
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            onSave(f.stringValue.trimmingCharacters(in: .whitespaces))
        }
        rebuildMenu()
    }

    @objc private func editPeer() {
        prompt(title: "Gateway override",
               message: "Leave empty to let Aether scan for the best gateway.\n"
                + "Set an address only if you want a fixed one.",
               value: Cfg.peer, placeholder: "e.g. 162.159.192.1:443"
        ) { Cfg.peer = $0 }
    }

    @objc private func editBind() {
        prompt(title: "SOCKS5 listen address",
               message: "Where Clash and other apps connect to Aether.",
               value: Cfg.bind, placeholder: "127.0.0.1:1819"
        ) {
            Cfg.bind = $0.isEmpty ? "127.0.0.1:1819" : $0
        }
    }

    @objc private func editExtra() {
        prompt(title: "Extra flags",
               message: "Appended to the aether command line.\n"
                + "Takes effect on the next connect.",
               value: Cfg.extra, placeholder: "--tor, --mim-peer a:b, AETHER_X=1 …"
        ) { Cfg.extra = $0 }
    }

    // MARK: NSWindowDelegate

    /// The user closed a window with the red button (not through a menu
    /// item), so drop our references here. Without this the old text view
    /// stays reachable from appendLog() and writing to it after the window
    /// is gone crashes the app on the second open.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        if closing === logWindow {
            logView = nil
            logWindow = nil
        }
    }

    // MARK: system proxy

    @objc private func setSystemProxy(_ sender: NSMenuItem) {
        let on = sender.tag == 1
        let port = Cfg.port
        let state = on ? "on" : "off"
        let script = """
        do shell script "networksetup -listallnetworkservices | tail -n +2 | while read s; do \
        case \\"$s\\" in '*'*) ;; *) \
        if echo \\"$s\\" | grep -qE 'Wi-Fi|Ethernet'; then \
        networksetup -setsocksfirewallproxy \\"$s\\" 127.0.0.1 \(port) >/dev/null; \
        networksetup -setsocksfirewallproxystate \\"$s\\" \(state) >/dev/null; \
        echo \\"$s\\"; fi ;; esac; done" with administrator privileges
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
        if let error = error {
            let msg = error[NSAppleScript.errorMessage] as? String ?? "unknown error"
            appendLog("!! system proxy: \(msg)")
            alert("Could not change the system proxy", msg)
        } else {
            appendLog(on ? "■ system proxy set to 127.0.0.1:\(port)"
                        : "■ system proxy cleared")
        }
    }

    private func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.alertStyle = .warning
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}

// MARK: - login item (LaunchAgent)

enum LoginItem {
    static let plist = NSHomeDirectory() + "/Library/LaunchAgents/com.cluvex.aethergui.plist"

    static func set(_ on: Bool) {
        let uid = String(getuid())
        if on {
            guard Bundle.main.bundlePath.hasSuffix(".app") else {
                Cfg.loginItem = false
                return
            }
            let content = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Label</key><string>com.cluvex.aethergui</string>
              <key>ProgramArguments</key>
              <array><string>/usr/bin/open</string><string>-a</string><string>\(Bundle.main.bundlePath)</string></array>
              <key>RunAtLoad</key><true/>
            </dict>
            </plist>
            """
            try? content.write(toFile: plist, atomically: true, encoding: .utf8)
            run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plist])
        } else {
            run("/bin/launchctl", ["bootout", "gui/\(uid)", "com.cluvex.aethergui"])
            try? FileManager.default.removeItem(atPath: plist)
        }
        Cfg.loginItem = on
    }

    private static func run(_ path: String, _ args: [String]) {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: path)
        t.arguments = args
        t.standardOutput = FileHandle.nullDevice
        t.standardError = FileHandle.nullDevice
        try? t.run()
        t.waitUntilExit()
    }
}

// MARK: - entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
