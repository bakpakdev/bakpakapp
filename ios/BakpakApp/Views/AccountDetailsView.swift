import SwiftUI

struct AccountDetailsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var graduationDate = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 15)) ?? Date()
    @State private var isSaving = false
    @State private var comingSoonMessage: String?

    private var emailDisplay: String {
        let email = authVM.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "Not set" : email
    }

    private var universityDisplay: String {
        campusTheme.fullName
    }

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.14))
                .frame(width: 260, height: 260)
                .blur(radius: 55)
                .offset(x: -130, y: -90)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 60)
                .offset(x: 150, y: 80)
                .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    EditProfileSectionHeader(
                        title: "Login",
                        subtitle: "Private account credentials — not shown on your profile"
                    )
                    EditProfileCard {
                        EditProfileRow(label: "Email") {
                            Text(emailDisplay)
                                .font(Theme.syne(15))
                                .foregroundStyle(campusTheme.textMuted)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 200, alignment: .trailing)
                        }
                        EditProfileRow(label: "Password & login", showDivider: false) {
                            Button {
                                comingSoonMessage = "Login management is coming soon."
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Manage")
                                        .font(Theme.syne(15, weight: .medium))
                                        .foregroundStyle(campusTheme.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(campusTheme.textMuted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    EditProfileSectionHeader(
                        title: "Campus",
                        subtitle: "Tied to your account — badge visibility is in Privacy settings"
                    )
                    EditProfileCard {
                        EditProfileRow(label: "School") {
                            Text(universityDisplay)
                                .font(Theme.syne(15))
                                .foregroundStyle(campusTheme.textMuted)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 200, alignment: .trailing)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Graduation")
                                .font(Theme.syne(15, weight: .medium))
                                .foregroundStyle(campusTheme.textPrimary)
                            DatePicker(
                                "Graduation date",
                                selection: $graduationDate,
                                in: graduationRange,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                            .frame(height: 140)
                            .clipped()
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                    }

                    Button {
                        // Account deletion flow — hook to backend when available
                    } label: {
                        Text("Delete Account")
                            .font(Theme.syne(15, weight: .semibold))
                            .foregroundStyle(Color(hex: "#E11D48"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: "#E11D48").opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    .padding(.top, 28)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Account Details")
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().tint(campusTheme.primary)
                    } else {
                        Text("Save")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                .disabled(isSaving)
            }
        }
        .toolbarBackground(campusTheme.surface.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.primary)
        .onAppear { load() }
        .alert("Account", isPresented: Binding(
            get: { comingSoonMessage != nil },
            set: { if !$0 { comingSoonMessage = nil } }
        )) {
            Button("OK", role: .cancel) { comingSoonMessage = nil }
        } message: {
            Text(comingSoonMessage ?? "")
        }
    }

    private var graduationRange: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2020, month: 1, day: 1)) ?? Date()
        let end = cal.date(from: DateComponents(year: 2034, month: 12, day: 31)) ?? Date()
        return start...end
    }

    private func load() {
        let d = UserDefaults.standard
        if let stored = d.string(forKey: EditProfilePrefs.gradYear), !stored.isEmpty {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsed = formatter.date(from: stored) {
                graduationDate = parsed
            } else if let year = Int(stored), year >= 2020, year <= 2034 {
                graduationDate = Calendar.current.date(from: DateComponents(year: year, month: 6, day: 15)) ?? graduationDate
            }
        }
    }

    private func saveLocal() {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        UserDefaults.standard.set(formatter.string(from: graduationDate), forKey: EditProfilePrefs.gradYear)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        saveLocal()
        dismiss()
    }
}
