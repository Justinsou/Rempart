import AppKit
import SwiftUI

/// Empêche le X de quitter : la fenêtre se cache, Rempart reste actif.
@MainActor
final class WindowKeepAlive: NSObject, NSWindowDelegate {
    static let shared = WindowKeepAlive()
    private var watched = Set<ObjectIdentifier>()

    func watch(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        guard !watched.contains(id) else { return }
        watched.insert(id)
        window.delegate = self
        // Le bouton rouge cache seulement — pas de Cmd+W destructeur.
        window.standardWindowButton(.closeButton)?.toolTip = "Masquer Rempart (reste actif)"
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

/// Structure SwiftUI pour attacher le délégué à la fenêtre hôte.
struct KeepAliveWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let w = view.window { WindowKeepAlive.shared.watch(w) }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { WindowKeepAlive.shared.watch(w) }
    }
}

/// Quitter Rempart demande une confirmation + 30 secondes d'attente.
@MainActor
final class QuitGuard: ObservableObject {
    static let shared = QuitGuard()
    static let waitSeconds = 30

    @Published var isPresented = false
    @Published var countdown: Int = waitSeconds
    private var timer: Timer?
    private var allowOnce = false

    func requestQuit() {
        // La feuille est sur la fenêtre principale : on la ramène au premier plan.
        AppRouter.shared.showMain(tab: AppRouter.shared.tab)
        countdown = Self.waitSeconds
        isPresented = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                if self.countdown > 0 { self.countdown -= 1 }
                else { t.invalidate() }
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isPresented = false
        countdown = Self.waitSeconds
    }

    func confirm() {
        guard countdown <= 0 else { return }
        timer?.invalidate()
        allowOnce = true
        isPresented = false
        NSApp.terminate(nil)
    }

    /// Appelé par AppDelegate : autorise une seule fois après confirmation.
    func shouldAllowTerminate() -> Bool {
        if allowOnce {
            allowOnce = false
            return true
        }
        requestQuit()
        return false
    }
}

struct QuitConfirmSheet: View {
    @ObservedObject private var quitGuard = QuitGuard.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
            Text("Quitter Rempart ?").font(.title2.bold())
            Text("Sans Rempart, tes apps et sites ne sont plus bloqués. Prends 30 secondes pour confirmer.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ProgressView(value: Double(QuitGuard.waitSeconds - quitGuard.countdown),
                         total: Double(QuitGuard.waitSeconds))
                .tint(Theme.accent)
            Text(quitGuard.countdown > 0 ? "\(quitGuard.countdown) s" : "Tu peux confirmer")
                .font(.headline.monospacedDigit())
            HStack {
                Button("Rester protégé") { quitGuard.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Quitter quand même") { quitGuard.confirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(quitGuard.countdown > 0)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}
