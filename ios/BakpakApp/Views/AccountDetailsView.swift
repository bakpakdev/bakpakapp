import SwiftUI

struct AccountDetailsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var graduationMonth = 6
    @State private var graduationYear = 2026
    @State private var draftMonth = 6
    @State private var draftYear = 2026
    @State private var showGraduationPicker = false
    @State private var isSaving = false
    @State private var comingSoonMessage: String?

    private let graduationMonths = Calendar.current.monthSymbols
    private let graduationYears = Array(2020...2034)

    private var emailDisplay: String {
        let email = authVM.user?.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return email.isEmpty ? "Not set" : email
    }

    private var universityDisplay: String {
        campusTheme.fullName
    }

    private var graduationLabel: String {
        "\(graduationMonths[graduationMonth - 1]) \(graduationYear)"
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
                        EditProfileRow(label: "Graduation", showDivider: false) {
                            Button {
                                draftMonth = graduationMonth
                                draftYear = graduationYear
                                showGraduationPicker = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text(graduationLabel)
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

                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save")
                                    .font(Theme.syne(15, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(campusTheme.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    .disabled(isSaving)
                    .padding(.top, 28)

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
                    .padding(.top, 12)
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
        }
        .toolbarBackground(campusTheme.surface.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(campusTheme.isDark ? .dark : .light, for: .navigationBar)
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .tint(campusTheme.primary)
        .onAppear { load() }
        .sheet(isPresented: $showGraduationPicker) {
            graduationPickerSheet
                .environment(\.campusTheme, campusTheme)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .alert("Account", isPresented: Binding(
            get: { comingSoonMessage != nil },
            set: { if !$0 { comingSoonMessage = nil } }
        )) {
            Button("OK", role: .cancel) { comingSoonMessage = nil }
        } message: {
            Text(comingSoonMessage ?? "")
        }
    }

    private var graduationPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    showGraduationPicker = false
                }
                .font(Theme.syne(15, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)

                Spacer()

                Text("Graduation")
                    .font(Theme.syne(16, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                Spacer()

                Button("Save") {
                    graduationMonth = draftMonth
                    graduationYear = draftYear
                    showGraduationPicker = false
                }
                .font(Theme.syne(15, weight: .bold))
                .foregroundStyle(campusTheme.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 8)

            HStack(spacing: 0) {
                Picker("Month", selection: $draftMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(graduationMonths[month - 1]).tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Year", selection: $draftYear) {
                    ForEach(graduationYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 180)
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .background(campusTheme.background.ignoresSafeArea())
    }

    private func load() {
        let d = UserDefaults.standard
        if let stored = d.string(forKey: EditProfilePrefs.gradYear), !stored.isEmpty {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            if let parsed = formatter.date(from: stored) {
                let parts = Calendar.current.dateComponents([.year, .month], from: parsed)
                if let month = parts.month { graduationMonth = month }
                if let year = parts.year, graduationYears.contains(year) { graduationYear = year }
            } else if let year = Int(stored), graduationYears.contains(year) {
                graduationYear = year
                graduationMonth = 6
            }
        }
    }

    private func saveLocal() {
        let value = String(format: "%04d-%02d-15", graduationYear, graduationMonth)
        UserDefaults.standard.set(value, forKey: EditProfilePrefs.gradYear)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        saveLocal()
        dismiss()
    }
}
