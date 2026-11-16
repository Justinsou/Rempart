import SwiftUI
import AppKit

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let path: String
    let searchTerms: [String]
    var id: String { bundleID }
    var blocked: BlockedApp { BlockedApp(bundleID: bundleID, name: name, path: path) }

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

