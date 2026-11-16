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

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                let protectedNow = store.activeSessions.isEmpty
                ZStack {
                    RoundedRectangle(cornerRadius: 32).fill(Theme.card)
                    RadialGradient(colors: [(protectedNow ? Mood.calm.center : Mood.happy.center).opacity(0.28), .clear],
                                   center: .center, startRadius: 10, endRadius: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 32))
                    VStack(spacing: 16) {
                        BlobView(mood: protectedNow ? .calm : .happy, size: 150)
                            .padding(.top, 22)
                        Text(protectedNow ? "Rempart veille sur toi" : "Déblocage en cours")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text("\(store.apps.count) app\(store.apps.count > 1 ? "s" : "") · \(store.sites.count) site\(store.sites.count > 1 ? "s" : "") sous surveillance")
                            .foregroundStyle(Theme.muted)
                            .padding(.bottom, 24)
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

                if !store.activeSessions.isEmpty {
                    HStack { Text("En cours").caption2Label(); Spacer() }.padding(.top, 6)
                    ForEach(store.activeSessions) { s in
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.items.map(store.name(for:)).joined(separator: ", "))
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    Text(s.reason).font(.callout).foregroundStyle(Theme.muted).lineLimit(2)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(remaining(s)).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                                    Button("Re-bloquer") { store.endSession(s) }
                                        .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.callout.weight(.medium))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        }
    }

    private func remaining(_ s: UnlockSession) -> String {
        let t = max(0, Int(s.end.timeIntervalSince(store.now)))
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
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
