import SwiftUI

struct SitesView: View {
    @EnvironmentObject var store: RulesStore
    @State private var input = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Sites web",
                       subtitle: "Bloqués dans ton navigateur et sur tout le Mac.",
                       mood: .sleepy,
                       badge: store.sites.isEmpty ? nil : "\(store.sites.count) bloqué\(store.sites.count > 1 ? "s" : "")")

            HStack(spacing: 12) {
                SearchField(text: $input, placeholder: "Ajouter un site (ex. youtube.com)", icon: "globe", onSubmit: askAdd)
                PillButton(title: "Bloquer", icon: "plus", action: askAdd)
                    .scaleEffect(1.1).padding(.horizontal, 6)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(Color(red: 1, green: 0.45, blue: 0.5))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggestions").caption2Label()
                        SuggestionChips()
                    }
                    if !store.sites.isEmpty {
                        Banner(icon: "lock.fill", text: "Tu peux ajouter des sites à tout moment. Pour en retirer un, débloque-le d'abord avec une justification.")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sites bloqués").caption2Label()
                        if store.sites.isEmpty {
                            HStack { Spacer()
                                VStack(spacing: 10) {
                                    BlobView(mood: .happy, size: 80)
                                    Text("Aucun site pour l'instant").foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }.padding(.vertical, 20)
                        }
                        ForEach(store.sites) { SiteRow(site: $0) }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 20)
    }

    private func askAdd() {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        guard let domain = RulesStore.normalize(raw) else {
            error = "Domaine invalide ou déjà présent."
            return
        }
        if store.isSiteListed(domain) {
            error = "Domaine invalide ou déjà présent."
            return
        }
        error = nil
        BlockConfirm.shared.ask(toBlock: domain, kind: "visiter ce site") {
            if store.addSite(domain) { input = "" }
            else { error = "Domaine invalide ou déjà présent." }
        }
    }
}

struct SiteRow: View {
    @EnvironmentObject var store: RulesStore
    let site: BlockedSite

    var body: some View {
        let unlocked = store.isSiteUnlockedNow(site.domain)
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: "globe").foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(site.domain).font(.system(size: 15, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle().fill(unlocked ? Mood.happy.center : Theme.accent).frame(width: 6, height: 6)
                    Text(unlocked ? "Débloqué temporairement" : "Bloqué")
                        .font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            RuleAction(key: site.key, listed: true, canRemove: store.canRemoveSite(site.domain),
                       unlockedNow: unlocked, onAdd: {}, onRemove: { store.removeSite(site) })
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SuggestionChips: View {
    @EnvironmentObject var store: RulesStore
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Suggestions.sites, id: \.domain) { s in
                let on = store.isSiteListed(s.domain)
                Button {
                    if on {
                        // Pendant la configuration initiale seulement.
                        if let site = store.sites.first(where: { $0.domain == s.domain }) { store.removeSite(site) }
                    } else {
                        BlockConfirm.shared.ask(toBlock: s.name, kind: "visiter \(s.domain)") {
                            store.addSite(s.domain)
                        }
                    }
                } label: {
                    Label(s.name, systemImage: on ? "checkmark.circle.fill" : "plus")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(on ? Theme.accent : .white)
                        .background(on ? Theme.accent.opacity(0.16) : Theme.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
