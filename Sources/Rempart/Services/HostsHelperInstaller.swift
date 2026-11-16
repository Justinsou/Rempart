import Foundation
import ServiceManagement

@MainActor
enum HostsHelperInstaller {
    static let plistPath = "/Library/LaunchDaemons/com.rempart.hosts.plist"
    static let installedScript = "/Library/Application Support/Rempart/hosts-daemon.sh"

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    private static func version(at path: String) -> Int? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").prefix(5) where line.contains("REMPART_DAEMON_VERSION=") {
            return Int(line.split(separator: "=").last ?? "")
        }
        return nil
    }

    static var bundledVersion: Int? {
        guard let res = Bundle.main.resourcePath else { return nil }
        return version(at: res + "/rempart-hosts-daemon.sh")
    }
    static var installedVersion: Int? { version(at: installedScript) }

    /// Le service est absent ou plus ancien que celui livré avec l'app.
    static var needsInstallOrUpdate: Bool {
        !isInstalled || (installedVersion ?? 0) < (bundledVersion ?? 0)
    }

    @discardableResult
    static func install() -> Bool { runAdmin("install") }

    @discardableResult
    static func uninstall() -> Bool { runAdmin("uninstall") }

    private static func runAdmin(_ action: String) -> Bool {
        guard let res = Bundle.main.resourcePath,
              res.hasPrefix("/Applications/") else { return false }   // jamais depuis un dossier modifiable (build/)
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let src = """
        do shell script "/bin/bash " & quoted form of "\(esc(res + "/install-daemon.sh"))" & " \(action) " & quoted form of "\(esc(res))" with administrator privileges
        """
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        RulesStore.shared.syncHosts()
        return err == nil
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }
}
