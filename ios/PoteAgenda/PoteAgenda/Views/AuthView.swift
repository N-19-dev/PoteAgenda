import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var mode: Mode = .login
    @State private var showingForgotPassword = false
    @State private var showingPrivacyPolicy = false

    enum Mode {
        case login
        case signup
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PoteAgenda")
                        .font(.largeTitle.bold())
                    Text("Trouve un créneau libre sans exposer ton agenda.")
                        .foregroundStyle(.secondary)
                }

                Picker("", selection: $mode) {
                    Text("Connexion").tag(Mode.login)
                    Text("Inscription").tag(Mode.signup)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    if mode == .signup {
                        TextField("Pseudo", text: $username)
                            .poteUsernameInputTraits()
                    }
                    TextField("Email", text: $email)
                        .poteEmailInputTraits()
                    SecureField("Mot de passe", text: $password)
                        .potePasswordInputTraits(isNewPassword: mode == .signup)
                }
                .textFieldStyle(.roundedBorder)

                if mode == .login {
                    Button("Mot de passe oublié ?") {
                        showingForgotPassword = true
                    }
                    .font(.footnote)
                }

                Button {
                    Task {
                        if mode == .login {
                            await sessionStore.signIn(email: email, password: password)
                        } else {
                            await sessionStore.signUp(email: email, password: password, username: username)
                        }
                    }
                } label: {
                    ZStack {
                        Label(mode == .login ? "Se connecter" : "Créer le compte", systemImage: "arrow.right")
                            .opacity(sessionStore.isLoading ? 0 : 1)
                        if sessionStore.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionStore.isLoading || email.isEmpty || password.isEmpty || (mode == .signup && username.isEmpty))

                VStack(alignment: .leading, spacing: 4) {
                    Label("Ton agenda détaillé ne sera jamais partagé.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Politique de confidentialité") {
                        showingPrivacyPolicy = true
                    }
                    .font(.caption)
                }

                Spacer()
            }
            .padding(24)
        }
        .sheet(isPresented: $showingForgotPassword) {
            ForgotPasswordView()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
    }
}

private struct ForgotPasswordView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var isSending = false
    @State private var confirmationMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Indique ton email : si un compte existe, tu recevras un lien pour choisir un nouveau mot de passe.")
                    .foregroundStyle(.secondary)

                TextField("Email", text: $email)
                    .poteEmailInputTraits()
                    .textFieldStyle(.roundedBorder)

                if let confirmationMessage {
                    Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                Button {
                    Task {
                        isSending = true
                        _ = await sessionStore.resetPassword(email: email)
                        isSending = false
                        confirmationMessage = "Si un compte existe pour cet email, un lien de réinitialisation vient d'être envoyé."
                    }
                } label: {
                    HStack {
                        Text("Envoyer le lien")
                        if isSending {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(24)
            .navigationTitle("Mot de passe oublié")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

private struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("PoteAgenda a été conçu pour que ton agenda détaillé ne quitte jamais ton contrôle.")
                        .font(.headline)
                    Text("Tes amis et les membres de tes groupes ne voient jamais le titre, la couleur, le lieu ou la note d'un de tes événements. Ils voient uniquement si tu es \"Libre\" ou \"Occupé\" sur un créneau donné.")
                    Text("Le partage de disponibilité passe par des fonctions serveur dédiées qui ne renvoient que l'identifiant de la personne et les horaires du créneau — jamais le contenu.")
                    Text("Si tu importes un calendrier de ton appareil, seul le créneau \"Occupé\" est envoyé par défaut, sans titre réel, sauf si tu actives explicitement l'import des titres dans les réglages.")
                    Text("Ta position, si tu actives les rappels de départ, reste sur ton appareil : elle n'est jamais stockée sur le serveur ni partagée avec tes amis.")
                }
                .foregroundStyle(.primary)
                .padding(24)
            }
            .navigationTitle("Confidentialité")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
