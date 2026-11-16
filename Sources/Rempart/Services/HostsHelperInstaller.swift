import Foundation
import ServiceManagement

@MainActor
enum HostsHelperInstaller {
    static let plistPath = "/Library/LaunchDaemons/com.rempart.hosts.plist"

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistPath) }

    @discardableResult
    static func install() -> Bool { runAdmin("install") }

    @discardableResult
    static func uninstall() -> Bool { runAdmin("uninstall") }

    private static func runAdmin(_ action: String) -> Bool {
        guard let res = Bundle.main.resourcePath else { return false }
        let cmd = "/bin/bash '\(res)/install-daemon.sh' \(action) '\(res)'"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(escaped)\" with administrator privileges"
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
