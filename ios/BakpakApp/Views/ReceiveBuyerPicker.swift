import SwiftUI

/// Receive payment, step one: when people made offers in chat, the seller picks who's buying.
/// An accepted offer sets the price; anyone else pays the listing price.
struct ReceiveBuyerPicker: View {
    let offers: [ListingOfferBuyer]
    let listingCents: Int
    let onPick: (ListingOfferBuyer?) -> Void
    let onCancel: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who are you selling to?")
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("Only that person can pay. An accepted offer sets the price.")
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(.top, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(offers) { offer in
                        Button { onPick(offer) } label: { row(offer) }
                            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                    }
                    Button { onPick(nil) } label: { someoneElseRow }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
                }
            }

            Button("Cancel", action: onCancel)
                .font(Theme.syne(15, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(campusTheme.background.ignoresSafeArea())
    }

    private func row(_ offer: ListingOfferBuyer) -> some View {
        let handle = offer.username.isEmpty ? "buyer" : "@\(offer.username)"
        return HStack(spacing: 12) {
            AvatarView(
                urlString: offer.avatarUrl,
                size: 44,
                initials: String((offer.name.isEmpty ? offer.username : offer.name).prefix(1)).uppercased()
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.name.isEmpty ? handle : offer.name)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Text(offer.accepted
                     ? "Accepted offer \(money(offer.amountCents))"
                     : "Offered \(money(offer.amountCents)) · pays \(money(listingCents)) unless accepted")
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(offer.accepted ? campusTheme.primary : campusTheme.textMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(money(offer.accepted ? offer.amountCents : listingCents))
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
        .padding(14)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(offer.accepted ? campusTheme.primary : campusTheme.border, lineWidth: offer.accepted ? 1.5 : 1)
        )
    }

    private var someoneElseRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Someone else")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("Anyone at the meetup can pay the listing price")
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
            }
            Spacer(minLength: 8)
            Text(money(listingCents))
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
        .padding(14)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(campusTheme.border, lineWidth: 1)
        )
    }

    private func money(_ cents: Int) -> String {
        cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%.2f", Double(cents) / 100)
    }
}
