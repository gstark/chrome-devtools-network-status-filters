// Helium Dev is the default browser. It opens Helium with the DevTools frontend in its Resources folder.
import AppKit
import UniformTypeIdentifiers

let heliumBundleID = "net.imput.helium"
let frontendFlag = "--custom-devtools-frontend"

let frontendURL = Bundle.main.resourceURL!.appendingPathComponent("devtools-frontend", isDirectory: false)

// The arguments of a running process, or nil if the system does not give them.
func arguments(of pid: pid_t) -> [String]? {
    var mib = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > 4 else { return nil }
    // The buffer is argc, the executable path, padding, then argv.
    let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
    let parts = buffer[4..<size].split(separator: 0)
    return parts.dropFirst().prefix(Int(argc)).map { String(decoding: $0, as: UTF8.self) }
}

func showAlert(_ message: String, _ detail: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = message
    alert.informativeText = detail
    alert.runModal()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pending: [URL] = []
    private var ready = false
    private var busy = false

    func application(_ application: NSApplication, open urls: [URL]) {
        pending += urls
        if ready { process() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--make-default") {
            makeDefault { NSApp.terminate(nil) }
            return
        }
        // Ask once to become the default browser. The Homebrew sandbox cannot open the app to do this at install.
        let offeredKey = "OfferedDefaultBrowser"
        let offered = UserDefaults.standard.bool(forKey: offeredKey)
        UserDefaults.standard.set(true, forKey: offeredKey)
        // Give the launch Apple Event time to deliver its URLs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let start = {
                self.ready = true
                self.process()
            }
            if offered { start() } else { self.makeDefault(then: start) }
        }
    }

    private func process() {
        guard !busy else { return }
        busy = true
        let urls = pending
        pending = []
        deliver(urls) {
            self.busy = false
            if self.pending.isEmpty {
                NSApp.terminate(nil)
            } else {
                self.process()
            }
        }
    }

    private func deliver(_ urls: [URL], done: @escaping () -> Void) {
        guard let heliumURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: heliumBundleID) else {
            showAlert("Helium is not installed", "Install Helium, then open the link again.")
            done()
            return
        }
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: heliumBundleID).first,
              let args = arguments(of: running.processIdentifier),
              !args.contains(where: { $0.hasPrefix(frontendFlag + "=") })
        else {
            open(urls, in: heliumURL, done: done)
            return
        }
        // Helium runs with the stock DevTools. A running Helium ignores new arguments, so it must restart.
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Helium runs with the stock DevTools"
        alert.informativeText = "Helium started without Helium Dev. Restart Helium to load your DevTools? Helium reopens your windows only if \"Continue where you left off\" is on."
        alert.addButton(withTitle: "Restart Helium")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            open(urls, in: heliumURL, done: done)
            return
        }
        running.terminate()
        waitForExit(of: running, triesLeft: 100) { exited in
            if exited {
                self.open(urls, in: heliumURL, done: done)
            } else {
                showAlert("Helium did not quit", "Quit Helium, then open the link again.")
                done()
            }
        }
    }

    private func waitForExit(of app: NSRunningApplication, triesLeft: Int, done: @escaping (Bool) -> Void) {
        if app.isTerminated { return done(true) }
        if triesLeft == 0 { return done(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.waitForExit(of: app, triesLeft: triesLeft - 1, done: done)
        }
    }

    private func open(_ urls: [URL], in heliumURL: URL, done: @escaping () -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["\(frontendFlag)=\(frontendURL.absoluteString)"]
        let completion: (NSRunningApplication?, Error?) -> Void = { _, error in
            DispatchQueue.main.async {
                if let error { showAlert("Helium did not open", error.localizedDescription) }
                done()
            }
        }
        if urls.isEmpty {
            NSWorkspace.shared.openApplication(at: heliumURL, configuration: configuration, completionHandler: completion)
        } else {
            NSWorkspace.shared.open(urls, withApplicationAt: heliumURL, configuration: configuration, completionHandler: completion)
        }
    }

    // Make Helium Dev the default browser and the default app for HTML files.
    private func makeDefault(then done: @escaping () -> Void) {
        let appURL = Bundle.main.bundleURL
        LSRegisterURL(appURL as CFURL, true)
        let workspace = NSWorkspace.shared
        var steps: [(@escaping (Error?) -> Void) -> Void] = []
        for scheme in ["http", "https"] where workspace.urlForApplication(toOpen: URL(string: "\(scheme)://")!) != appURL {
            steps.append { workspace.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme, completion: $0) }
        }
        for type in [UTType.html, UTType(importedAs: "public.xhtml")] where workspace.urlForApplication(toOpen: type) != appURL {
            steps.append { workspace.setDefaultApplication(at: appURL, toOpen: type, completion: $0) }
        }
        runSteps(steps, then: done)
    }

    private func runSteps(_ steps: [(@escaping (Error?) -> Void) -> Void], then done: @escaping () -> Void) {
        guard let step = steps.first else { return done() }
        step { error in
            DispatchQueue.main.async {
                if let error {
                    showAlert("Helium Dev is not the default browser", error.localizedDescription)
                    return done()
                }
                self.runSteps(Array(steps.dropFirst()), then: done)
            }
        }
    }
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
