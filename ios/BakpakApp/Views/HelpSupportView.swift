import SwiftUI

struct HelpSupportView: View {
    @EnvironmentObject private var appState: AppState
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
                            safetyLine(icon: "creditcard", text: "Pay in the app with Apple Pay or a card. Don’t send Venmo, Cash App, or Zelle.")
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
                                answer: "Open the meetup from Inbox or Meetups, then tap Pay (buyer) or Receive (seller). Use Apple Pay or a card. Don’t pay outside the app."
                            )
                            faqRow(
                                id: "cashout",
                                question: "How do I cash out?",
                                answer: "You get the full listing price; buyers pay a small popup service fee on top. Turn on two-factor in Settings first, then open Settings → Cash out setup and set up payouts with Stripe once (a few minutes). After that every sale goes straight to your Stripe account and on to your bank or debit card, usually in about 2 business days. Sales from before you set up wait in your popup balance and move over as soon as you finish."
                            )
                            faqRow(
                                id: "meetup",
                                question: "How do meetups work?",
                                answer: "On a listing, tap Meetup request and pick a campus spot and time. Chat starts only after the seller accepts. If they decline, you’ll get a notification. Open Meetups from Inbox for what’s next, then check in and pay in-app when you’re both there."
                            )
                            faqRow(
                                id: "sold",
                                question: "When is an item marked sold?",
                                answer: "After the in-app payment goes through for that listing, the item is marked sold and leaves the shop grid."
                            )
                            faqRow(
                                id: "report",
                                question: "How do I report someone?",
                                answer: "In a chat, tap ⋯ → Report. Pick a reason, add details if you want, and submit. We’ll get the report at \(SupportMail.address). You can also block them at the same time.",
                                showDivider: false
                            )
                        }
                        .background(CampusCardBackground())
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SettingsSectionTitle(title: "contact")
                        VStack(spacing: 0) {
                            Button {
                                Motion.haptic(.light)
                                appState.path.append(.contactSupport)
                            } label: {
                                navLabel(
                                    icon: "envelope",
                                    title: "Email support",
                                    subtitle: SupportMail.address
                                )
                            }
                            .buttonStyle(.plain)
                            divider
                            Link(destination: LegalLinks.terms) {
                                navLabel(icon: "doc.text", title: "Terms & community rules", subtitle: "Be decent. No scams, hate, or off-campus pickups.")
                            }
                            .buttonStyle(.plain)
                            divider
                            Link(destination: LegalLinks.privacy) {
                                navLabel(icon: "lock.doc", title: "Privacy Policy", subtitle: "We use your campus email to keep listings on campus. We don’t sell your data.")
                            }
                            .buttonStyle(.plain)
                        }
                        .background(CampusCardBackground())
                    }

                    Text("popup for iOS \(Self.versionLabel)")
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

    /// "1.0 (2)" so testers can say which TestFlight build they're on.
    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
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
