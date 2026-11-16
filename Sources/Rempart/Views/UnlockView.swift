import SwiftUI

struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        Card {
            HStack(spacing: 10) {
                Text("\(number)").font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.03, green: 0.12, blue: 0.2))
                    .frame(width: 22, height: 22).background(Theme.accent, in: Circle())
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .padding(.bottom, 4)
            content
        }
    }
}

struct UnlockView: View {
    @EnvironmentObject var store: RulesStore
    @EnvironmentObject var router: AppRouter
    @State private var selected = Set<String>()
    @State private var minutes = 60
    @State private var reason = ""
    @State private var countdown: Int?
    @State private var timer: Timer?
    @State private var done = false

    static let minChars = 50
    static let wait = 60

    private var durations: [(String, Int)] {
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        let untilMidnight = max(1, Int(midnight.timeIntervalSinceNow / 60))
        return [("15 min", 15), ("30 min", 30), ("1 h", 60), ("2 h", 120), ("Jusqu'à minuit", untilMidnight)]
    }

    private var items: [(key: String, name: String)] {
        store.apps.map { ($0.key, $0.name) } + store.sites.map { ($0.key, $0.domain) }
    }

    private var chars: Int { reason.trimmingCharacters(in: .whitespacesAndNewlines).count }
    private var remainingChars: Int { max(0, Self.minChars - chars) }
    private var canRequest: Bool { !selected.isEmpty && remainingChars == 0 && countdown == nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Débloquer",
                           subtitle: "Explique pourquoi. Ton texte est gardé dans le journal.",
                           mood: countdown == nil ? .happy : .sleepy)

                if items.isEmpty {
                    VStack(spacing: 12) {
                        BlobView(mood: .calm, size: 100)
                        Text("Rien à débloquer").font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text("Ajoute d'abord des apps ou des sites à bloquer.").foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    StepCard(number: 1, title: "Quoi débloquer") {
                        FlowLayout(spacing: 8) {
                            ForEach(items, id: \.key) { it in
                                let on = selected.contains(it.key)
                                Button {
                                    if on { selected.remove(it.key) } else { selected.insert(it.key) }
                                } label: {
                                    Label(it.name, systemImage: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 14).padding(.vertical, 8)
                                        .foregroundStyle(on ? Theme.accent : .white)
                                        .background(on ? Theme.accent.opacity(0.18) : Theme.bg, in: Capsule())
                                }
                                .buttonStyle(.plain).disabled(countdown != nil)
                            }
                        }
                    }

                    StepCard(number: 2, title: "Combien de temps") {
                        FlowLayout(spacing: 8) {
                            ForEach(durations, id: \.1) { d in
                                let on = minutes == d.1
                                Button { minutes = d.1 } label: {
                                    Text(d.0).font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 16).padding(.vertical, 8)
                                        .foregroundStyle(on ? Color(red: 0.03, green: 0.12, blue: 0.2) : .white)
                                        .background(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.bg), in: Capsule())
                                }
                                .buttonStyle(.plain).disabled(countdown != nil)
                            }
                        }
                    }

                    StepCard(number: 3, title: "Pourquoi") {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $reason)
                                .font(.system(size: 14, design: .rounded))
                                .scrollContentBackground(.hidden)
                                .padding(10).frame(minHeight: 120)
                                .background(Theme.bg, in: RoundedRectangle(cornerRadius: 16))
                                .disabled(countdown != nil)
                            if reason.isEmpty {
                                Text("Ex. : soirée film du samedi, ou formation SEO pour mon travail (YouTube)…")
                                    .foregroundStyle(Theme.muted).padding(.horizontal, 16).padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        HStack(spacing: 10) {
                            ProgressView(value: Double(min(chars, Self.minChars)), total: Double(Self.minChars))
                                .tint(remainingChars == 0 ? Theme.accent : .orange)
                            Text(remainingChars > 0 ? "\(chars)/\(Self.minChars)" : "Parfait")
                                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(remainingChars > 0 ? .orange : Theme.accent)
                        }
                    }

                    if let c = countdown {
                        Card {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().stroke(Theme.bg, lineWidth: 6)
                                    Circle().trim(from: 0, to: CGFloat(Self.wait - c) / CGFloat(Self.wait))
                                        .stroke(Theme.accent, style: .init(lineWidth: 6, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text("\(c)").font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                                }
                                .frame(width: 60, height: 60)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prends un instant").font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Text("En as-tu vraiment besoin ?").foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                PillButton(title: "Annuler", style: .subtle) { cancel() }
                                if c == 0 { PillButton(title: "Confirmer", icon: "lock.open.fill") { confirm() } }
                            }
                        }
                    } else {
                        Button { startCountdown() } label: {
                            Text("Demander le déblocage")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .foregroundStyle(Color(red: 0.03, green: 0.12, blue: 0.2))
                                .background(Theme.gradient.opacity(canRequest ? 1 : 0.3), in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain).disabled(!canRequest)
                    }

                    if done {
                        Banner(icon: "checkmark.circle.fill", text: "Débloqué ! Tu peux maintenant retirer l'élément de la liste si besoin. Bon usage.")
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .onAppear { applyPreselect() }
        .onChange(of: router.preselect) { _, _ in applyPreselect() }
    }

    private func applyPreselect() {
        guard !router.preselect.isEmpty else { return }
        selected.formUnion(router.preselect)
        router.preselect = []
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
