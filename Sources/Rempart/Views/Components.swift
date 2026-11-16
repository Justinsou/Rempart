import SwiftUI

struct PageHeader: View {
    let title: String
    var subtitle: String?
    var mood: Mood = .calm
    var badge: String?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text(title).screenTitle()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Theme.accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let subtitle {
                    Text(subtitle).foregroundStyle(Theme.muted).font(.system(size: 14, design: .rounded))
                }
            }
            Spacer()
            BlobView(mood: mood, size: 54, glow: false)
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder: String
    var icon = "magnifyingglass"
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15, design: .rounded))
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct PillButton: View {
    let title: String
    var icon: String?
    var style: Style = .primary
    let action: () -> Void
    enum Style { case primary, subtle, danger, locked }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
                Text(title).font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
        }
        .buttonStyle(.plain)
    }
    private var fg: Color {
        switch style {
        case .primary: Color(red: 0.03, green: 0.12, blue: 0.2)
        case .subtle: .white
        case .danger: Color(red: 1, green: 0.45, blue: 0.5)
        case .locked: Theme.muted
        }
    }
    private var bg: AnyShapeStyle {
        switch style {
        case .primary: AnyShapeStyle(Theme.accent)
        case .subtle: AnyShapeStyle(Color.white.opacity(0.1))
        case .danger: AnyShapeStyle(Color(red: 1, green: 0.3, blue: 0.4).opacity(0.15))
        case .locked: AnyShapeStyle(Color.white.opacity(0.06))
        }
    }
}

struct Banner: View {
    let icon: String
    let text: String
    var tint: Color = Theme.accent
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(text).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SegmentedTabs<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let on = o.0 == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = o.0 } } label: {
                    Text(o.1).font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundStyle(on ? .white : Theme.muted)
                        .background(on ? Color.white.opacity(0.12) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: Capsule())
    }
}

/// Étiquette d'état + action selon que l'élément est libre, verrouillé ou débloqué.
struct RuleAction: View {
    @EnvironmentObject var store: RulesStore
    let key: String                 // "app:..." ou "site:..."
    let listed: Bool
    let canRemove: Bool
    let unlockedNow: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if !listed {
            PillButton(title: "Bloquer", icon: "plus", action: onAdd)
        } else if canRemove {
            PillButton(title: "Retirer", icon: "minus", style: .danger, action: onRemove)
        } else {
            PillButton(title: "Verrouillé", icon: "lock.fill", style: .locked) {
                AppRouter.shared.preselect = [key]
                AppRouter.shared.tab = .unlock
            }
            .help("Pour le retirer, débloque-le d'abord avec une justification.")
        }
    }
}
