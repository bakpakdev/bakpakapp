import SwiftUI

struct HelpSupportView: View {
    @Environment(\.campusTheme) private var campusTheme
    @State private var expandedFAQ: String?

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    CampusPageHeader(title: "help", subtitle: "safety & support")

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "campus safety")
                        VStack(alignment: .leading, spacing: 12) {
                            safetyLine(icon: "building.2", text: "Meet in public campus spots — unions, libraries, dining halls.")
                            safetyLine(icon: "creditcard", text: "Pay in-app with Apple Pay. Don’t send Venmo, Cash App, or Zelle.")
                            safetyLine(icon: "person.2", text: "If a chat feels off, leave and block them from their profile.")
                            safetyLine(icon: "exclamationmark.bubble", text: "popup never asks for your password or bank login in a message.")
                        }
                        .padding(16)
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "common questions")
                        VStack(spacing: 0) {
                            faqRow(
                                id: "pay",
                                question: "How do I pay for a meetup?",
                                answer: "Open the meetup from Inbox, tap Pay, and use Apple Pay. The seller collects on their phone. Don’t pay outside the app."
                            )
                            faqRow(
                                id: "cashout",
                                question: "How do I cash out?",
                                answer: "Tap to Pay sales sit in your popup balance. Open Settings → Cash out setup, connect Square, then cash out to your bank."
                            )
                            faqRow(
                                id: "meetup",
                                question: "How do meetups work?",
                                answer: "Propose a campus spot and time in chat. When both people accept, it shows under meetup reminders. Meet in public and complete payment in-app."
                            )
                            faqRow(
                                id: "sold",
                                question: "When is an item marked sold?",
                                answer: "After Apple Pay goes through for that listing, the item is marked sold and leaves the shop grid."
                            )
                            faqRow(
                                id: "report",
                                question: "How do I report someone?",
                                answer: "Block them from their profile, then email us with their username and a screenshot of the chat. We’ll review it.",
                                showDivider: false
                            )
                        }
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "contact")
                        VStack(spacing: 0) {
                            if let mail = URL(string: "mailto:hello@popup.app?subject=popup%20support") {
                                Link(destination: mail) {
                                    navLabel(icon: "envelope", title: "Email support", subtitle: "hello@popup.app")
                                }
                                .buttonStyle(.plain)
                                divider
                            }
                            navLabel(icon: "doc.text", title: "Community guidelines", subtitle: "Be decent. No scams, hate, or off-campus pickups.")
                            divider
                            navLabel(icon: "lock.doc", title: "Privacy", subtitle: "We use your campus email to keep listings on campus. We don’t sell your data.")
                        }
                        .background(CampusCardBackground())
                    }

                    Text("popup for iOS")
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .campusPageStyle()
    }

    private func safetyLine(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 42, height: 42)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(text)
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textPrimary)
                .padding(.top, 10)
        }
    }

    private func faqRow(id: String, question: String, answer: String, showDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(Motion.snappy) {
                    expandedFAQ = expandedFAQ == id ? nil : id
                }
                Motion.haptic(.light)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(question)
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: expandedFAQ == id ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, expandedFAQ == id ? 8 : 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedFAQ == id {
                Text(answer)
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            if showDivider {
                Rectangle()
                    .fill(campusTheme.border)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func navLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 42, height: 42)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.syne(15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text(subtitle)
                    .font(Theme.syne(12))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(campusTheme.border)
            .frame(height: 1)
            .padding(.leading, 70)
    }
}
