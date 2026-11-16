import SwiftUI
import AppKit

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let path: String
    let searchTerms: [String]
    var id: String { bundleID }
    var blocked: BlockedApp { BlockedApp(bundleID: bundleID, name: name) }

    /// Noms plus clairs pour certaines apps système (ex. TV → Apple TV).
    private static let friendlyNames: [String: String] = [
        "com.apple.TV": "Apple TV",
        "com.apple.Music": "Apple Music",
        "com.apple.podcasts": "Podcasts",
        "com.apple.iBooksX": "Livres",
        "com.apple.news": "News",
        "com.apple.Photos": "Photos",
        "com.apple.MobileSMS": "Messages",
        "com.apple.FaceTime": "FaceTime",
        "com.apple.Safari": "Safari",
        "com.apple.mail": "Mail",
        "com.apple.iCal": "Calendrier",
        "com.apple.Notes": "Notes",
        "com.apple.AppStore": "App Store",
        "com.apple.systempreferences": "Réglages Système",
        "com.apple.SystemPreferences": "Réglages Système"
    ]

    private static let skippedPrefixes = [
        "com.apple.dt.", "com.apple.CoreSimulator", "com.apple.Simulator",
        "com.apple.WebKit.", "com.apple.LoginUI", "com.apple.notificationcenterui"
    ]

    static func scan() -> [InstalledApp] {
        var out: [String: InstalledApp] = [:]

        let dirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications"
        ]
        for d in dirs { collect(fromDirectory: d, into: &out) }

        // Spotlight : apps ailleurs (Setapp, Homebrew cask, etc.)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = ["kMDItemContentTypeTree == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let paths = String(data: data, encoding: .utf8)?
            .split(separator: "\n").map(String.init) ?? []
        for p in paths { add(path: p, into: &out) }

        // Apps déjà ouvertes (au cas où)
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let url = app.bundleURL { add(path: url.path, into: &out) }
        }

        return out.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func collect(fromDirectory dir: String, into out: inout [String: InstalledApp]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for f in items where f.hasSuffix(".app") {
            add(path: dir + "/" + f, into: &out)
        }
    }

    private static func add(path: String, into out: inout [String: InstalledApp]) {
        guard path.hasSuffix(".app"),
              let b = Bundle(path: path),
              let id = b.bundleIdentifier,
              id != Bundle.main.bundleIdentifier,
              id != "com.apple.finder",
              !skippedPrefixes.contains(where: { id.hasPrefix($0) }) else { return }

        // Évite les helpers / extensions / apps internes
        if path.contains(".app/Contents/") { return }
        if path.contains("/Xcode.app/") || path.contains("/Xcode-beta.app/") { return }

        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let display = FileManager.default.displayName(atPath: path)
        let plistName = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
        let friendly = friendlyNames[id]
        let name = friendly ?? (display.isEmpty ? nil : display) ?? plistName ?? fileName

        var terms = Set([name, fileName, display, plistName, id].compactMap { $0 }.filter { !$0.isEmpty })
        if let friendly { terms.insert(friendly); terms.insert("Apple " + fileName) }
        // Recherche "Apple TV" même si le fichier s'appelle TV
        if fileName == "TV" || id == "com.apple.TV" {
            terms.formUnion(["Apple TV", "TV+", "appletv", "AppleTV"])
        }

        // Préfère /Applications ou /System/Applications aux chemins obscurs
        if let existing = out[id] {
            let score: (String) -> Int = { p in
                if p.hasPrefix("/System/Applications") { return 3 }
                if p.hasPrefix("/Applications") { return 2 }
                return 1
            }
            if score(path) <= score(existing.path) { return }
        }
        out[id] = InstalledApp(bundleID: id, name: name, path: path, searchTerms: Array(terms))
    }
}

struct AppRow: View {
    @EnvironmentObject var store: RulesStore
    let app: InstalledApp
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 32, height: 32)
            Text(app.name)
            Spacer()
            Toggle("", isOn: Binding(get: { store.isAppListed(app.bundleID) },
                                     set: { _ in store.toggleApp(app.blocked) }))
                .toggleStyle(.switch).labelsHidden().tint(Theme.accent)
        }
        .padding(.vertical, 2)
    }
}

struct AppsView: View {
    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var loading = true

    var filtered: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter { app in
            app.searchTerms.contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apps").screenTitle()
            Text("Active l'interrupteur pour bloquer une app. Elle sera fermée dès qu'elle s'ouvre.")
                .foregroundStyle(.secondary)
            TextField("Rechercher (ex. Apple TV, Safari…)", text: $query)
                .textFieldStyle(.roundedBorder)
            if loading {
                ProgressView("Chargement des apps…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("\(filtered.count) app\(filtered.count > 1 ? "s" : "")")
                    .font(.caption).foregroundStyle(.secondary)
                List(filtered) { AppRow(app: $0) }
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
        .task {
            loading = true
            let scanned = await Task.detached(priority: .userInitiated) { InstalledApp.scan() }.value
            apps = scanned
            loading = false
        }
    }
}

struct SitesView: View {
    @EnvironmentObject var store: RulesStore
    @State private var input = ""
    @State private var error = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sites web").screenTitle()
            HStack {
                TextField("exemple.com", text: $input).textFieldStyle(.roundedBorder).onSubmit(add)
                Button("Ajouter", action: add).buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            if error { Text("Domaine invalide ou déjà présent.").font(.caption).foregroundStyle(.red) }

            Text("Suggestions").font(.headline)
            SuggestionChips()

            Text("Bloqués").font(.headline)
            List {
                ForEach(store.sites) { s in
                    HStack {
                        Image(systemName: "globe").foregroundStyle(Theme.accent)
                        Text(s.domain)
                        Spacer()
                        Button { store.removeSite(s) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
    }

    private func add() {
        error = !store.addSite(input)
        if !error { input = "" }
    }
}

struct SuggestionChips: View {
    @EnvironmentObject var store: RulesStore
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Suggestions.sites, id: \.domain) { s in
                let on = store.isSiteListed(s.domain)
                Button {
                    if on { if let site = store.sites.first(where: { $0.domain == s.domain }) { store.removeSite(site) } }
                    else { store.addSite(s.domain) }
                } label: {
                    Label(s.name, systemImage: on ? "checkmark.circle.fill" : "plus.circle")
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(on ? Theme.accent.opacity(0.25) : Theme.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 600, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(bounds.width, subviews)
        for (i, p) in r.points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var pts: [CGPoint] = []
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += s.width + spacing; rowH = max(rowH, s.height); maxW = max(maxW, x)
        }
        return (CGSize(width: maxW, height: y + rowH), pts)
    }
}
