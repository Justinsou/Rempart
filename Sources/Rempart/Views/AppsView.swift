import SwiftUI
import AppKit

struct AppRow: View {
    @EnvironmentObject var store: RulesStore
    let app: InstalledApp

    var body: some View {
        let listed = store.isAppListed(app.bundleID)
        let unlocked = store.isAppUnlockedNow(app.bundleID)
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable().frame(width: 40, height: 40)
                .saturation(listed && !unlocked ? 0.85 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle().fill(statusColor(listed, unlocked)).frame(width: 6, height: 6)
                    Text(statusText(listed, unlocked)).font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            RuleAction(key: "app:" + app.bundleID, listed: listed,
                       canRemove: store.canRemoveApp(app.bundleID), unlockedNow: unlocked,
                       displayName: app.name, kindLabel: "ouvrir cette app",
                       onAdd: { store.toggleApp(app.blocked) },
                       onRemove: { store.toggleApp(app.blocked) })
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(listed ? Theme.card : Theme.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
    }

    private func statusColor(_ listed: Bool, _ unlocked: Bool) -> Color {
        !listed ? Theme.muted : (unlocked ? Mood.happy.center : Theme.accent)
    }
    private func statusText(_ listed: Bool, _ unlocked: Bool) -> String {
        !listed ? "Libre" : (unlocked ? "Débloquée temporairement" : "Bloquée")
    }
}

struct AppsView: View {
    @EnvironmentObject var store: RulesStore
    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var loading = true
    @State private var filter = Filter.all
    enum Filter { case all, blocked }

    var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return apps.filter { app in
            (filter == .all || store.isAppListed(app.bundleID)) &&
            (q.isEmpty || app.searchTerms.contains { $0.localizedCaseInsensitiveContains(q) })
        }
        .sorted { a, b in
            let la = store.isAppListed(a.bundleID), lb = store.isAppListed(b.bundleID)
            if la != lb { return la }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Apps",
                       subtitle: "Une app bloquée est fermée dès qu'elle s'ouvre.",
                       mood: .sad,
                       badge: store.apps.isEmpty ? nil : "\(store.apps.count) bloquée\(store.apps.count > 1 ? "s" : "")")
            HStack(spacing: 12) {
                SearchField(text: $query, placeholder: "Rechercher (ex. Apple TV, Safari…)")
                SegmentedTabs(options: [(Filter.all, "Toutes"), (.blocked, "Bloquées")], selection: $filter)
            }
            if !store.apps.isEmpty {
                Banner(icon: "lock.fill", text: "Tu peux ajouter des apps à tout moment. Pour en retirer une, débloque-la d'abord avec une justification.")
            }
            if loading {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                VStack(spacing: 10) {
                    BlobView(mood: .sleepy, size: 90)
                    Text("Aucune app trouvée").font(.system(size: 17, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { AppRow(app: $0) }
                    }
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 20)
        .task {
            loading = true
            apps = await Task.detached(priority: .userInitiated) { InstalledApp.scan() }.value
            loading = false
        }
    }
}
