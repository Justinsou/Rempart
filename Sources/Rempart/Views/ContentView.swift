import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RulesStore
    @EnvironmentObject var router: AppRouter

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: Binding(get: { router.tab }, set: { router.tab = $0 ?? .dashboard })) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.gradient)
                    Text("Rempart").font(.title3.weight(.bold))
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        } detail: {
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
        .sheet(isPresented: Binding(get: { !store.onboarded }, set: { _ in })) {
            OnboardingView().environmentObject(store).interactiveDismissDisabled()
        }
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: RulesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let protectedNow = store.activeSessions.isEmpty
                HStack(spacing: 16) {
                    Image(systemName: protectedNow ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 44)).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(protectedNow ? "Protégé" : "Déblocage en cours").font(.largeTitle.bold())
                        Text("\(store.apps.count) app\(store.apps.count > 1 ? "s" : "") et \(store.sites.count) site\(store.sites.count > 1 ? "s" : "") sous surveillance")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(24)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 20))

                HStack(spacing: 14) {
                    Card {
                        Label("Blocages aujourd'hui", systemImage: "hand.raised").foregroundStyle(.secondary)
                        Text("\(store.blocksToday)").font(.system(size: 40, weight: .bold, design: .rounded))
                    }
                    Card {
                        Label("Déblocages actifs", systemImage: "timer").foregroundStyle(.secondary)
                        Text("\(store.activeSessions.count)").font(.system(size: 40, weight: .bold, design: .rounded))
                    }
                }

                if !store.activeSessions.isEmpty {
                    Text("En cours").font(.headline)
                    ForEach(store.activeSessions) { s in
                        Card {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(s.items.map(store.name(for:)).joined(separator: ", ")).font(.headline)
                                    Text(s.reason).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(remaining(s)).font(.title3.monospacedDigit().bold())
                                    Button("Re-bloquer") { store.endSession(s) }.buttonStyle(.link)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
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
                Text("Journal").font(.largeTitle.bold())
                Spacer()
                Toggle("Filtrer par date", isOn: $filter).toggleStyle(.switch)
                if filter {
                    DatePicker("", selection: Binding(get: { day ?? Date() }, set: { day = $0 }), displayedComponents: .date)
                        .labelsHidden()
                }
            }
            if entries.isEmpty {
                ContentUnavailableView("Aucune entrée", systemImage: "book.closed",
                                       description: Text("Tes justifications de déblocage apparaîtront ici."))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(entries) { e in
                            Card {
                                HStack {
                                    Text(e.itemNames.joined(separator: ", ")).font(.headline)
                                    Spacer()
                                    Text("\(e.minutes) min").foregroundStyle(.secondary)
                                }
                                Text(e.reason)
                                Text(e.date.formatted(date: .complete, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(28)
    }
}
