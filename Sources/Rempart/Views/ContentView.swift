import SwiftUI

extension View {
    func screenTitle() -> some View {
        font(.system(size: 32, weight: .bold, design: .rounded))
    }
    func caption2Label() -> some View {
        font(.system(size: 11, weight: .semibold, design: .rounded)).textCase(.uppercase)
            .tracking(0.8).foregroundStyle(Theme.muted)
    }
}

struct ContentView: View {
    @EnvironmentObject var store: RulesStore
    @EnvironmentObject var router: AppRouter

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Group {
                switch router.tab {
                case .dashboard: DashboardView()
                case .apps: AppsView()
                case .sites: SitesView()
                case .unlock: UnlockView()
                case .circle: CircleView()
                case .journal: JournalView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: Binding(get: { !store.onboarded }, set: { _ in })) {
            OnboardingView().environmentObject(store).interactiveDismissDisabled()
        }
    }
}

struct Sidebar: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var store: RulesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                BlobView(mood: .calm, size: 34, glow: false, float: false)
                Text("Rempart").font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .padding(.top, 44).padding(.bottom, 22).padding(.horizontal, 6)

            ForEach(Tab.allCases) { tab in
                let on = router.tab == tab
                Button { withAnimation(.snappy(duration: 0.2)) { router.tab = tab } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon).frame(width: 20)
                            .foregroundStyle(on ? Theme.accent : Theme.muted)
                        Text(tab.title).font(.system(size: 14, weight: on ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(on ? .white : Theme.muted)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(on ? Theme.card : .clear, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(store.activeSessions.isEmpty ? Theme.accent : Mood.happy.center).frame(width: 8, height: 8)
                Text(store.activeSessions.isEmpty ? "Protégé" : "Débloqué").font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
            }
            .padding(12)
        }
        .padding(.horizontal, 14).padding(.bottom, 14)
        .frame(width: 220)
        .background(Theme.sidebar)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let mood: Mood
    var body: some View {
        Card {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).caption2Label()
                    Text(value).font(.system(size: 40, weight: .bold, design: .rounded))
                }
                Spacer()
                BlobView(mood: mood, size: 46, glow: false, float: false)
            }
        }
    }
}

struct WeekChart: View {
    @EnvironmentObject var store: RulesStore
    var body: some View {
        let data = store.lastDays(7)
        let maxV = max(1, data.map(\.count).max() ?? 1)
        Card {
            Text("Blocages · 7 jours").caption2Label()
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(data.enumerated()), id: \.offset) { i, d in
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(Theme.bg).frame(width: 22, height: 110)
                            Capsule()
                                .fill(i == data.count - 1 ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.accent.opacity(0.35)))
                                .frame(width: 22, height: max(8, 110 * CGFloat(d.count) / CGFloat(maxV)))
                        }
                        Text(d.label).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 6)
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: RulesStore
    @State private var needsHelper = HostsHelperInstaller.needsInstallOrUpdate

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if needsHelper {
                    Card {
                        HStack(spacing: 14) {
                            Image(systemName: "exclamationmark.shield.fill").font(.title2).foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(HostsHelperInstaller.isInstalled ? "Mettre à jour la protection" : "Active la protection permanente")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text("Sans elle, les apps bloquées peuvent s'ouvrir quand Rempart est fermé.")
                                    .font(.callout).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            PillButton(title: HostsHelperInstaller.isInstalled ? "Mettre à jour" : "Installer", icon: "lock.shield") {
                                _ = HostsHelperInstaller.install()
                                needsHelper = HostsHelperInstaller.needsInstallOrUpdate
                            }
                        }
                    }
                }
                if let pause = store.freshPause, store.activeSessions.contains(where: { $0.id == pause.id }) {
                    PauseBanner(session: pause) { store.freshPause = nil }
                }
                if store.activeSessions.isEmpty {
                    IdleHero()
                } else {
                    ForEach(store.activeSessions) { s in
                        PauseClock(session: s)
                    }
                }

                HStack(spacing: 14) {
                    StatTile(label: "Blocages aujourd'hui", value: "\(store.blocksToday)", mood: .angry)
                    StatTile(label: "Déblocages actifs", value: "\(store.activeSessions.count)", mood: .happy)
                }
                HStack(spacing: 14) {
                    StatTile(label: "Apps bloquées", value: "\(store.apps.count)", mood: .sad)
                    StatTile(label: "Sites bloqués", value: "\(store.sites.count)", mood: .sleepy)
                }
                WeekChart()

            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
    }
}

/// État calme : rien n'est débloqué.
private struct IdleHero: View {
    @EnvironmentObject var store: RulesStore
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32).fill(Theme.card)
            RadialGradient(colors: [Mood.calm.center.opacity(0.28), .clear],
                           center: .center, startRadius: 10, endRadius: 260)
                .clipShape(RoundedRectangle(cornerRadius: 32))
            VStack(spacing: 16) {
                BlobView(mood: .calm, size: 150).padding(.top, 22)
                Text("Rempart veille sur toi")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("\(store.apps.count) app\(store.apps.count > 1 ? "s" : "") · \(store.sites.count) site\(store.sites.count > 1 ? "s" : "") sous surveillance")
                    .foregroundStyle(Theme.muted)
                    .padding(.bottom, 24)
            }
        }
    }
}

/// Annonce courte au moment où la pause commence. Elle se ferme ; le compte à rebours reste.
private struct PauseBanner: View {
    let session: UnlockSession
    let dismiss: () -> Void
    @EnvironmentObject var store: RulesStore
    var body: some View {
        Card {
            HStack(spacing: 14) {
                BlobView(mood: .happy, size: 54, glow: false, float: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text("C'est parti").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(session.items.map(store.name(for:)).joined(separator: ", ")) · \(Int(session.end.timeIntervalSince(session.start) / 60)) min accordées")
                        .font(.callout).foregroundStyle(Theme.muted)
                }
                Spacer()
                PillButton(title: "OK", icon: "checkmark", action: dismiss)
            }
        }
    }
}

/// Compte à rebours d'une pause : temps restant, durée accordée, heure de fin. Ne bloque pas l'écran.
private struct PauseClock: View {
    let session: UnlockSession
    @EnvironmentObject var store: RulesStore

    var body: some View {
        let total = max(1, session.end.timeIntervalSince(session.start))
        let left = max(0, session.end.timeIntervalSince(store.now))
        let fraction = left / total
        ZStack {
            RoundedRectangle(cornerRadius: 32).fill(Theme.card)
            RadialGradient(colors: [Mood.happy.center.opacity(0.22), .clear],
                           center: .center, startRadius: 10, endRadius: 280)
                .clipShape(RoundedRectangle(cornerRadius: 32))
            HStack(spacing: 28) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: fraction)
                    VStack(spacing: 2) {
                        Text(clock(left))
                            .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                        Text("restant").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.items.map(store.name(for:)).joined(separator: ", "))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(Int(total / 60)) min accordées · jusqu'à \(session.end.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(Theme.muted)
                    Text(session.reason).font(.callout).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                    PillButton(title: "Re-bloquer maintenant", icon: "lock.fill", style: .danger) {
                        store.endSession(session)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let t = Int(seconds)
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct JournalView: View {
    @EnvironmentObject var store: RulesStore
    @State private var day: Date?
    @State private var filter = false

    var entries: [JournalEntry] {
        store.journal.filter { !filter || Calendar.current.isDate($0.date, inSameDayAs: day ?? Date()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Journal").screenTitle()
                Spacer()
                Toggle("Filtrer par date", isOn: $filter).toggleStyle(.switch).tint(Theme.accent)
                if filter {
                    DatePicker("", selection: Binding(get: { day ?? Date() }, set: { day = $0 }), displayedComponents: .date)
                        .labelsHidden()
                }
            }
            if entries.isEmpty {
                VStack(spacing: 14) {
                    BlobView(mood: .sleepy, size: 110)
                    Text("Rien à signaler").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("Tes justifications de déblocage apparaîtront ici.").foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(entries) { e in
                            Card {
                                HStack {
                                    Text(e.itemNames.joined(separator: ", "))
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Spacer()
                                    Text("\(e.minutes) min").foregroundStyle(Theme.accent).font(.callout.weight(.semibold))
                                }
                                Text(e.reason)
                                Text(e.date.formatted(date: .complete, time: .shortened))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
    }
}
