import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var username = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var bio = ""

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Username", text: $username)
                TextField("First Name", text: $firstName)
                TextField("Last Name", text: $lastName)
                TextField("Bio", text: $bio, axis: .vertical)
            }
            Section {
                Button("Save Changes") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.uoGreen)
            }
        }
        .navigationTitle("Edit Profile")
        .onAppear {
            username = authVM.user?.username ?? ""
            firstName = authVM.user?.firstName ?? ""
            lastName = authVM.user?.lastName ?? ""
            bio = authVM.user?.bio ?? ""
        }
    }

    private func save() async {
        guard let userId = authVM.user?.id else { return }
        let payload: [String: Any] = [
            "username": username,
            "firstName": firstName,
            "lastName": lastName,
            "bio": bio
        ]
        do {
            let body = try JSONSerialization.data(withJSONObject: payload)
            let _: User = try await APIClient.shared.request(path: "/users/\(userId)", method: "PUT", body: body)
            await authVM.refreshMe()
        } catch { }
    }
}
