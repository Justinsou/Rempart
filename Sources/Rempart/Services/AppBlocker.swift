import AppKit
import SwiftUI

@MainActor
final class AppBlocker {
    static let shared = AppBlocker()
    private var timer: Timer?
    private var overlay: NSWindow?
    private var lastShown: [String: Date] = [:]

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.check(app) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                    self?.check(app)
                }
            }
        }
    }

    private func check(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier, id != "com.apple.finder",
              !app.isTerminated,
              RulesStore.shared.isAppBlocked(id) else { return }
        let name = app.localizedName ?? id
        let icon = app.icon
        app.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if !app.isTerminated { app.forceTerminate() }
        }
        // Évite de recompter / réafficher en boucle pendant la fermeture
        if let last = lastShown[id], Date().timeIntervalSince(last) < 4 { return }
        lastShown[id] = Date()
        RulesStore.shared.recordBlock()
        showOverlay(title: name, icon: icon)
    }

    func showOverlay(title: String, icon: NSImage?) {
        overlay?.close()
        let view = BlockOverlayView(title: title, icon: icon) { [weak self] in
            self?.overlay?.close()
            AppRouter.shared.showMain(tab: .unlock)
        } dismiss: { [weak self] in
            self?.overlay?.close()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.styleMask = [.titled, .fullSizeContentView, .closable]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.level = .floating
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 420, height: 340))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlay = w
    }
}

struct BlockOverlayView: View {
    let title: String
    let icon: NSImage?
    let unlock: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                BlobView(mood: .angry, size: 110)
                if let icon {
                    Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                        .shadow(radius: 6).offset(x: 14, y: 10)
                }
            }
            .padding(.top, 26)
            Text("\(title) est bloqué")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Rempart protège ton temps. Si tu as une vraie raison, explique-la pour débloquer temporairement.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
                .padding(.horizontal, 28)
            Spacer(minLength: 0)
            HStack {
                Button("Compris", action: dismiss).keyboardShortcut(.cancelAction).buttonStyle(.bordered)
                Button("Demander un déblocage", action: unlock)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .controlSize(.large)
            .padding(.bottom, 26)
        }
        .frame(width: 420, height: 360)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }
}
