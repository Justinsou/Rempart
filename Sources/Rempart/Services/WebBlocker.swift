import AppKit
import Foundation

@MainActor
final class WebBlocker {
    static let shared = WebBlocker()

    private struct Browser { let bundleID: String; let tabKind: String }
    private let browsers = [
        Browser(bundleID: "com.apple.Safari", tabKind: "current tab"),
        Browser(bundleID: "com.google.Chrome", tabKind: "active tab"),
        Browser(bundleID: "com.brave.Browser", tabKind: "active tab"),
        Browser(bundleID: "com.microsoft.edgemac", tabKind: "active tab"),
        Browser(bundleID: "company.thebrowser.Browser", tabKind: "active tab")
    ]
    private var timer: Timer?
    private var denied = Set<String>()

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    private func scan() {
        let store = RulesStore.shared
        guard !store.sites.isEmpty else { return }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for b in browsers where running.contains(b.bundleID) && !denied.contains(b.bundleID) {
            let listScript = """
            tell application id "\(b.bundleID)"
              set out to ""
              repeat with i from 1 to (count of windows)
                try
                  set out to out & i & "|" & (URL of \(b.tabKind) of window i) & linefeed
                end try
              end repeat
              return out
            end tell
            """
            guard let result = run(listScript, bundle: b.bundleID) else { continue }
            for line in result.components(separatedBy: "\n") {
                let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let idx = Int(parts[0]),
                      let host = URLComponents(string: parts[1])?.host,
                      let domain = store.isSiteBlocked(host: host) else { continue }
                redirect(b, window: idx, domain: domain)
            }
        }
    }

    private func redirect(_ b: Browser, window: Int, domain: String) {
        guard let res = Bundle.main.resourcePath else { return }
        let page = "file://" + res + "/block.html#" + domain
        let script = """
        tell application id "\(b.bundleID)"
          set URL of \(b.tabKind) of window \(window) to "\(page)"
        end tell
        """
        _ = run(script, bundle: b.bundleID)
        RulesStore.shared.recordBlock()
    }

    private func run(_ source: String, bundle: String) -> String? {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err, let code = err[NSAppleScript.errorNumber] as? Int, code == -1743 {
            denied.insert(bundle)   // automatisation refusée : on arrête d'insister
        }
        return result?.stringValue
    }
}
