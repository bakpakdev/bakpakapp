import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var showRegister: Bool

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("bakpak").font(.largeTitle).bold().foregroundStyle(Theme.uoGreen)
            TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            TextField("API URL", text: $authVM.baseURL).textFieldStyle(.roundedBorder)

            Button {
                Task { await authVM.login(email: email, password: password) }
            } label: {
                if authVM.isLoading { ProgressView() } else { Text("Log in").bold() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.uoGreen)

            if let error = authVM.errorMessage {
                Text(error).foregroundStyle(.red).font(.footnote)
            }

            Button("Need an account? Register") { showRegister = true }
                .font(.footnote)
        }
        .padding()
    }
}
