import MessageUI
import SwiftUI

struct ReportListingOption: Hashable, Identifiable {
    let productId: String
    let title: String
    let imageURL: String?
    let price: Double

    var id: String { productId }
}

struct ReportUserTarget: Hashable {
    let userId: String
    let displayName: String
    var conversationId: String = ""
    var listings: [ReportListingOption] = []
}

struct ReportUserView: View {
    let target: ReportUserTarget

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: String?
    @State private var details = ""
    @State private var selectedProductId = ""
    @State private var alsoBlock = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var didSubmit = false
    @State private var showMailComposer = false
    @State private var pendingMailSubject = ""
    @State private var pendingMailBody = ""

    private let reasons = [
        "Scam or fraud",
        "Harassment",
        "Spam",
        "Inappropriate",
        "Something else",
    ]

    private var canSubmit: Bool {
        selectedReason != nil && !isSubmitting && !didSubmit
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                CampusPageHeader(
                    title: "report",
                    subtitle: target.displayName.isEmpty ? "this person" : target.displayName
                )

                Text("Tell us what happened. We’ll review it — they won’t see your report.")
                    .font(Theme.syne(14, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("why are you reporting?")
                    VStack(spacing: 8) {
                        ForEach(reasons, id: \.self) { reason in
                            reasonRow(reason)
                        }
                    }
                }

                if !target.listings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("related listing")
                        Text("Optional — pick the item this is about.")
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                        ForEach(target.listings) { listing in
                            listingRow(listing)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("details")
                    ZStack(alignment: .topLeading) {
                        if details.isEmpty {
                            Text("Add anything that helps (optional)")
                                .font(Theme.syne(15))
                                .foregroundStyle(campusTheme.textMuted)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 16)
                        }
                        TextEditor(text: $details)
                            .font(Theme.syne(15))
                            .foregroundStyle(campusTheme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .frame(minHeight: 130)
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

                Button {
                    Motion.haptic(.light)
                    alsoBlock.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: alsoBlock ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(alsoBlock ? campusTheme.primary : campusTheme.textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Also block them")
                                .font(Theme.syne(15, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                            Text("They won’t show in your inbox")
                                .font(Theme.syne(12, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(campusTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(campusTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.syne(13, weight: .medium))
                        .foregroundStyle(Color(hex: "#E11D48"))
                }

                if didSubmit {
                    Text("Report sent. Thanks for helping keep popup safe.")
                        .font(Theme.syne(14, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Group {
                        if isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(didSubmit ? "Done" : "Submit report")
                                .font(Theme.syne(16, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(canSubmit || didSubmit ? campusTheme.primary : campusTheme.textMuted.opacity(0.4))
                    .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled((!canSubmit && !didSubmit) || isSubmitting)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(CampusPageBackground())
        .campusScreenStyle()
        .onAppear {
            if selectedProductId.isEmpty, target.listings.count == 1 {
                selectedProductId = target.listings[0].productId
            }
        }
        .sheet(isPresented: $showMailComposer) {
            MailComposeView(
                recipients: [SupportMail.address],
                subject: pendingMailSubject,
                body: pendingMailBody
            ) { result in
                showMailComposer = false
                if result == .failed {
                    errorMessage = "Report saved. Couldn’t open email — message us at \(SupportMail.address)."
                }
                finishAfterReport()
            }
            .ignoresSafeArea()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.syne(18, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)
    }

    private func reasonRow(_ reason: String) -> some View {
        let selected = selectedReason == reason
        return Button {
            Motion.haptic(.light)
            selectedReason = reason
        } label: {
            HStack(spacing: 12) {
                Text(reason)
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

    private func listingRow(_ listing: ReportListingOption) -> some View {
        let selected = selectedProductId == listing.productId
        return Button {
            Motion.haptic(.light)
            selectedProductId = selected ? "" : listing.productId
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: listing.imageURL ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    campusTheme.elevatedSurface
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(listing.title.isEmpty ? "Listing" : listing.title)
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(selected ? .white : campusTheme.textPrimary)
                        .lineLimit(1)
                    if listing.price > 0 {
                        Text(String(format: "$%.2f", listing.price))
                            .font(Theme.syne(12, weight: .medium))
                            .foregroundStyle(selected ? .white.opacity(0.8) : campusTheme.textMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? .white.opacity(0.9) : campusTheme.textMuted)
            }
            .padding(12)
            .background(selected ? campusTheme.primary : campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func submit() async {
        if didSubmit {
            dismissAfterSubmit()
            return
        }
        guard let reason = selectedReason else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await ReportService.submitUserReport(
                reportedUserId: target.userId,
                reason: reason,
                details: details,
                conversationId: target.conversationId,
                productId: selectedProductId.isEmpty ? nil : selectedProductId
            )
            if alsoBlock {
                await BlockStore.shared.block(
                    userId: target.userId,
                    name: target.displayName.isEmpty ? "User" : target.displayName
                )
            }
            Motion.haptic(.medium)
            didSubmit = true
            notifySupportByEmail(reason: reason)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn’t send your report. Try again."
            Motion.haptic(.light)
            isSubmitting = false
        }
    }

    private func notifySupportByEmail(reason: String) {
        let listing = target.listings.first(where: { $0.productId == selectedProductId })
        let reporter = authVM.user
        pendingMailSubject = "popup report — \(reason)"
        pendingMailBody = """
        User report from the popup app.

        Reason: \(reason)
        Details: \(details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : details.trimmingCharacters(in: .whitespacesAndNewlines))

        Reported user: \(target.displayName)
        Reported user ID: \(target.userId)
        Conversation ID: \(target.conversationId.isEmpty ? "—" : target.conversationId)
        Related listing: \(listing?.title ?? "—")
        Listing ID: \(selectedProductId.isEmpty ? "—" : selectedProductId)
        Also blocked: \(alsoBlock ? "yes" : "no")

        —
        Reporter: \(reporter?.username ?? "—")
        Reporter email: \(reporter?.email ?? "—")
        Reporter ID: \(reporter?.id ?? "—")
        """

        if SupportMail.canSendMail {
            isSubmitting = false
            showMailComposer = true
        } else if let url = SupportMail.mailtoURL(subject: pendingMailSubject, body: pendingMailBody) {
            UIApplication.shared.open(url)
            finishAfterReport()
        } else {
            finishAfterReport()
        }
    }

    private func finishAfterReport() {
        isSubmitting = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            dismissAfterSubmit()
        }
    }

    private func dismissAfterSubmit() {
        if alsoBlock {
            // Pop report + conversation when they also blocked.
            if appState.path.count >= 2 {
                appState.path.removeLast(2)
            } else if !appState.path.isEmpty {
                appState.path.removeLast()
            }
        } else if !appState.path.isEmpty {
            appState.path.removeLast()
        } else {
            dismiss()
        }
    }
}
