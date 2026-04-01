import SwiftUI

struct RegisterView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Binding var showRegister: Bool

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Create account").font(.title2).bold()
            TextField("Email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            TextField("Username", text: $username).textFieldStyle(.roundedBorder)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)

            Button {
                Task { await authVM.register(email: email, username: username, password: password) }
            } label: {
                if authVM.isLoading { ProgressView() } else { Text("Register").bold() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.uoGreen)

            if let error = authVM.errorMessage {
                Text(error).foregroundStyle(.red).font(.footnote)
            }

            Button("Already have an account? Log in") { showRegister = false }
                .font(.footnote)
        }
        .padding()
    }
}
