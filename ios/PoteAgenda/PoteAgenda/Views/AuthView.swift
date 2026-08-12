import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var mode: Mode = .login

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
                    Text("Trouve un creneau libre sans exposer ton agenda.")
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

                Button {
                    Task {
                        if mode == .login {
                            await sessionStore.signIn(email: email, password: password)
                        } else {
                            await sessionStore.signUp(email: email, password: password, username: username)
                        }
                    }
                } label: {
                    Label(mode == .login ? "Se connecter" : "Creer le compte", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(sessionStore.isLoading || email.isEmpty || password.isEmpty || (mode == .signup && username.isEmpty))

                Spacer()
            }
            .padding(24)
        }
    }
}
