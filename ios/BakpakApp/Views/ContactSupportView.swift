import MessageUI
import SwiftUI

struct ContactSupportView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTopic: String?
    @State private var message = ""
    @State private var showMailComposer = false
    @State private var errorMessage: String?
    @State private var didSend = false

    private let topics = [
        "Account help",
        "Payments / cash out",
        "Meetup issue",
        "Bug or feedback",
        "Something else",
    ]

    private var canSend: Bool {
        selectedTopic != nil
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    private var isBusy: Bool { showMailComposer }

    private var mailSubject: String {
        "popup support — \(selectedTopic ?? "help")"
    }

    private var mailBody: String {
        let user = authVM.user
        let name = [user?.firstName, user?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return """
        \(message.trimmingCharacters(in: .whitespacesAndNewlines))

        —
        Topic: \(selectedTopic ?? "help")
        Name: \(name.isEmpty ? "—" : name)
        Username: \(user?.username ?? "—")
        Email: \(user?.email ?? "—")
        User ID: \(user?.id ?? "—")
        """
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                CampusPageHeader(title: "contact", subtitle: "support")

                Text("Write your message here. We’ll get it at \(SupportMail.address).")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("what’s this about?")
                    VStack(spacing: 8) {
                        ForEach(topics, id: \.self) { topic in
                            topicRow(topic)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("message")
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("How can we help?")
                                .font(Theme.syne(15))
                                .foregroundStyle(campusTheme.textMuted)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                        }
                        TextEditor(text: $message)
                            .font(Theme.syne(15))
                            .foregroundStyle(campusTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .frame(minHeight: 150)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .fill(campusTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(campusTheme.border, lineWidth: 1)
                            )
                    )
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.syne(13, weight: .medium))
                        .foregroundStyle(Color(hex: "#E11D48"))
                }

                if didSend {
                    Text("Message ready — thanks for reaching out.")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                }

                Button {
                    sendSupport()
                } label: {
                    Text(didSend ? "Done" : "Email support")
                        .font(Theme.syne(16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(canSend || didSend ? campusTheme.primary : campusTheme.textMuted.opacity(0.4))
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled((!canSend && !didSend) || isBusy)

                Text(SupportMail.address)
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(CampusPageBackground())
        .campusScreenStyle()
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipients: [SupportMail.address],
                subject: mailSubject,
                body: mailBody
            ) { result in
                showMailComposer = false
                switch result {
                case .sent:
                    didSend = true
                    Motion.haptic(.medium)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        dismiss()
                    }
                case .failed:
                    errorMessage = "Couldn’t send email. Try again, or email \(SupportMail.address) directly."
                case .cancelled, .saved:
                    break
                @unknown default:
                    break
                }
            }
            .ignoresSafeArea()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.syne(18, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)
    }

    private func topicRow(_ topic: String) -> some View {
        let selected = selectedTopic == topic
        return Button {
            Motion.haptic(.light)
            selectedTopic = topic
        } label: {
            HStack(spacing: 12) {
                Text(topic)
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(selected ? .white : campusTheme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? .white.opacity(0.9) : campusTheme.textMuted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(selected ? campusTheme.primary : campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func sendSupport() {
        if didSend {
            dismiss()
            return
        }
        guard canSend else { return }
        errorMessage = nil
        Motion.haptic(.light)
        if SupportMail.canSendMail {
            showMailComposer = true
        } else if let url = SupportMail.mailtoURL(subject: mailSubject, body: mailBody) {
            UIApplication.shared.open(url)
            didSend = true
        } else {
            errorMessage = "Couldn’t open Mail. Email us at \(SupportMail.address)."
        }
    }
}
