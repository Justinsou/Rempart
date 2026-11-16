import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var store: RulesStore
    @State private var step = 0
    @State private var apps: [InstalledApp] = []
    @State private var daemon = HostsHelperInstaller.isInstalled
    @State private var login = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 18) {
            BlobView(mood: [Mood.calm, .happy, .sleepy, .sad][step], size: 90)
            Text(["Bienvenue dans Rempart", "Choisis les apps à bloquer", "Choisis les sites à bloquer", "Dernières autorisations"][step])
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Group {
                switch step {
                case 0:
                    Text("Rempart bloque tes apps et sites distrayants en permanence. Tu peux les débloquer temporairement en écrivant une vraie raison.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                case 1:
                    ScrollView {
                        LazyVStack(spacing: 8) { ForEach(apps) { AppRow(app: $0) } }
                    }
                    .frame(height: 300).scrollIndicators(.hidden)
                case 2:
                    SuggestionChips().frame(maxWidth: .infinity, alignment: .leading)
                    Text("Tu pourras en ajouter d'autres ensuite.").font(.caption).foregroundStyle(.secondary)
                default:
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Lancer Rempart au démarrage du Mac", isOn: $login)
                            .onChange(of: login) { _, v in LoginItem.set(v) }
                        HStack {
                            Image(systemName: daemon ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(daemon ? Theme.accent : .orange)
                            Text("Blocage de sites dans tous les navigateurs (mot de passe admin)")
                            Spacer()
                            if !daemon {
                                Button("Installer") { daemon = HostsHelperInstaller.install() }
                            }
                        }
                        Text("Au premier site bloqué, macOS te demandera d'autoriser Rempart à contrôler ton navigateur : accepte.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Retour") { step -= 1 } }
                Spacer()
                Button(step == 3 ? "Terminer" : "Continuer") {
                    if step == 3 { store.setOnboarded() } else { step += 1 }
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560, height: 560)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .task {
            apps = await Task.detached(priority: .userInitiated) { InstalledApp.scan() }.value
        }
    }
}
