import SwiftUI

struct UnlockView: View {
    @EnvironmentObject var store: RulesStore
    @State private var selected = Set<String>()
    @State private var minutes = 60
    @State private var reason = ""
    @State private var countdown: Int?
    @State private var timer: Timer?
    @State private var done = false

    static let minChars = 50
    static let wait = 60

    private var durations: [(String, Int)] {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date()).addingTimeInterval(86400)
        let untilMidnight = max(1, Int(midnight.timeIntervalSinceNow / 60))
        return [("15 min", 15), ("30 min", 30), ("1 h", 60), ("2 h", 120), ("Jusqu'à minuit", untilMidnight)]
    }

    private var items: [(key: String, name: String)] {
        store.apps.map { ($0.key, $0.name) } + store.sites.map { ($0.key, $0.domain) }
    }

    private var remainingChars: Int { max(0, Self.minChars - reason.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    private var canRequest: Bool { !selected.isEmpty && remainingChars == 0 && countdown == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Débloquer").font(.largeTitle.bold())
                Text("Explique pourquoi tu en as besoin. Ton texte est gardé dans le journal.")
                    .foregroundStyle(.secondary)

                if items.isEmpty {
                    ContentUnavailableView("Rien à débloquer", systemImage: "checkmark.shield",
                                           description: Text("Ajoute d'abord des apps ou des sites à bloquer."))
                } else {
                    Card {
                        Text("1. Quoi débloquer").font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(items, id: \.key) { it in
                                let on = selected.contains(it.key)
                                Button {
                                    if on { selected.remove(it.key) } else { selected.insert(it.key) }
                                } label: {
                                    Label(it.name, systemImage: on ? "checkmark.circle.fill" : "circle")
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(on ? Theme.accent.opacity(0.25) : Color.secondary.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Card {
                        Text("2. Combien de temps").font(.headline)
                        Picker("", selection: $minutes) {
                            ForEach(durations, id: \.1) { Text($0.0).tag($0.1) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                    }
                    Card {
                        Text("3. Pourquoi").font(.headline)
                        TextEditor(text: $reason)
                            .frame(minHeight: 110)
                            .scrollContentBackground(.hidden)
                            .padding(6)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .disabled(countdown != nil)
                        Text(remainingChars > 0 ? "Encore \(remainingChars) caractère\(remainingChars > 1 ? "s" : "") minimum"
                                                : "Justification suffisante")
                            .font(.caption).foregroundStyle(remainingChars > 0 ? .orange : Theme.accent)
                    }

                    if let c = countdown {
                        Card {
                            HStack {
                                ProgressView(value: Double(Self.wait - c), total: Double(Self.wait)).tint(Theme.accent)
                                Text("\(c) s").monospacedDigit().font(.headline)
                            }
                            Text("Prends un moment : en as-tu vraiment besoin ?").foregroundStyle(.secondary)
                            HStack {
                                Button("Annuler") { cancel() }
                                Button("Confirmer le déblocage") { confirm() }
                                    .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(c > 0)
                            }
                        }
                    } else {
                        Button("Demander le déblocage") { startCountdown() }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                            .controlSize(.large).disabled(!canRequest)
                    }
                    if done {
                        Label("Débloqué. Bon usage !", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(28)
        }
    }

    private func startCountdown() {
        done = false
        countdown = Self.wait
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            Task { @MainActor in
                if let c = countdown, c > 0 { countdown = c - 1 } else { t.invalidate() }
            }
        }
    }

    private func cancel() { timer?.invalidate(); countdown = nil }

    private func confirm() {
        timer?.invalidate()
        store.addUnlock(items: Array(selected), minutes: minutes,
                        reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
        selected = []; reason = ""; countdown = nil; done = true
    }
}
