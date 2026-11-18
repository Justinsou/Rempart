import SwiftUI
import AppKit

enum Theme {
    static let bg = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let sidebar = Color(red: 0.055, green: 0.055, blue: 0.065)
    static let card = Color(red: 0.115, green: 0.115, blue: 0.13)
    static let muted = Color(white: 0.55)
    static let accent = Color(red: 0.30, green: 0.70, blue: 0.97)
    static let accent2 = Color(red: 0.04, green: 0.50, blue: 0.86)
    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum Tab: String, CaseIterable, Identifiable {
    case dashboard, apps, sites, unlock, circle, journal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Tableau de bord"
        case .apps: "Apps"
        case .sites: "Sites web"
        case .unlock: "Débloquer"
        case .circle: "Proches"
        case .journal: "Journal"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "shield.lefthalf.filled"
        case .apps: "square.grid.2x2"
        case .sites: "globe"
        case .unlock: "lock.open"
        case .circle: "person.2"
        case .journal: "book.closed"
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab: Tab = .dashboard
    @Published var preselect: Set<String> = []
    var openWindow: (() -> Void)?

    func showMain(tab: Tab) {
        self.tab = tab
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow?()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        MainActor.assumeIsolated {
            _ = RulesStore.shared
            AppBlocker.shared.start()
            WebBlocker.shared.start()
            ApprovalService.shared.start()
            PauseNotifier.askPermission()
            for w in NSApp.windows where w.identifier?.rawValue.contains("main") == true {
                WindowKeepAlive.shared.watch(w)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            QuitGuard.shared.shouldAllowTerminate() ? .terminateNow : .terminateCancel
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppRouter.shared.showMain(tab: AppRouter.shared.tab) } }
        return true
    }
}

extension RempartApp {
    /// Compte à rebours court pour la barre de menus.
    static func remaining(_ s: UnlockSession, now: Date) -> String {
        let t = max(0, Int(s.end.timeIntervalSince(now)))
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

@main
struct RempartApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = RulesStore.shared
    @StateObject private var router = AppRouter.shared
    @StateObject private var quitGuard = QuitGuard.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Rempart", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(router)
                .frame(minWidth: 860, minHeight: 560)
                .background(KeepAliveWindow())
                .onAppear { router.openWindow = { openWindow(id: "main") } }
                .sheet(isPresented: $quitGuard.isPresented) {
                    QuitConfirmSheet()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quitter Rempart…") { QuitGuard.shared.requestQuit() }
                    .keyboardShortcut("q")
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(store)
        } label: {
            if let s = store.activeSessions.first {
                Text(Self.remaining(s, now: store.now))
            } else {
                Image(systemName: "shield.lefthalf.filled")
            }
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject var store: RulesStore
    var body: some View {
        if store.activeSessions.isEmpty {
            Text("Protégé")
        } else {
            Text("Pauses en cours")
            ForEach(store.activeSessions) { s in
                Text("\(s.items.map(store.name(for:)).joined(separator: ", ")) · \(RempartApp.remaining(s, now: store.now))")
            }
        }
        Divider()
        Button("Ouvrir Rempart") { AppRouter.shared.showMain(tab: .dashboard) }
        Button("Débloquer…") { AppRouter.shared.showMain(tab: .unlock) }
        Divider()
        Button("Quitter Rempart…") {
            AppRouter.shared.showMain(tab: .dashboard)
            QuitGuard.shared.requestQuit()
        }
    }
}
