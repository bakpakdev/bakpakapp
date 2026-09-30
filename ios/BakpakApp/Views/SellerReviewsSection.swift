import SwiftUI

// MARK: - Stars

struct ReviewStars: View {
    let rating: Double
    var size: CGFloat = 13
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: symbol(for: index))
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(campusTheme.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "%.1f out of 5 stars", rating))
    }

    private func symbol(for index: Int) -> String {
        let value = rating - Double(index - 1)
        if value >= 0.75 { return "star.fill" }
        if value >= 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - Review card

struct SellerReviewCard: View {
    let review: SellerReview
    @Environment(\.campusTheme) private var campusTheme

    private var dateLabel: String? {
        guard let date = review.createdAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: review.reviewerAvatar ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        campusTheme.elevatedSurface
                        Text(String(review.reviewerName.prefix(1)).uppercased())
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(review.reviewerName)
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(1)
                    ReviewStars(rating: Double(review.rating), size: 12)
                }

                Spacer(minLength: 8)

                if let dateLabel {
                    Text(dateLabel)
                        .font(Theme.syne(11, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }

            if let comment = review.comment {
                Text(comment)
                    .font(Theme.syne(14))
                    .foregroundStyle(campusTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let title = review.productTitle {
                HStack(spacing: 10) {
                    AsyncImage(url: URL(string: review.productImage ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.surface
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Bought: \(title)")
                        .font(Theme.syne(12, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(6)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(campusTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
        )
    }
}

// MARK: - Reviews tab content

struct SellerReviewsSection: View {
    let reviews: [SellerReview]
    let isLoading: Bool
    let isOwnProfile: Bool
    /// Items the viewer bought from this seller (empty on your own profile).
    let purchases: [ReviewablePurchase]
    let onLeaveReview: () -> Void

    @Environment(\.campusTheme) private var campusTheme

    private var summary: ReviewSummary { ReviewSummary(reviews: reviews) }
    private var unreviewedCount: Int { purchases.filter { $0.existingReview == nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLoading && reviews.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else {
                summaryCard

                if !isOwnProfile && !purchases.isEmpty {
                    leaveReviewButton
                }

                if reviews.isEmpty {
                    emptyState
                } else {
                    ForEach(reviews) { review in
                        SellerReviewCard(review: review)
                    }
                }
            }
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 16) {
            Text(summary.count == 0 ? "–" : String(format: "%.1f", summary.average))
                .font(Theme.syne(34, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 76, height: 76)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                ReviewStars(rating: summary.average, size: 15)
                Text(summary.count == 1 ? "1 review" : "\(summary.count) reviews")
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                Text("Only buyers who bought an item can review")
                    .font(Theme.syne(11, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(campusTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
        )
    }

    private var leaveReviewButton: some View {
        Button {
            Motion.haptic(.medium)
            onLeaveReview()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "star.bubble")
                    .font(.system(size: 14, weight: .semibold))
                Text(unreviewedCount > 0 ? "Leave a review" : "Edit your review")
                    .font(Theme.syne(15, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(campusTheme.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text("No reviews yet")
                .font(Theme.syne(17, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(isOwnProfile
                 ? "Reviews from campus buyers will land here."
                 : "Reviews from people who bought from this seller will show here.")
                .font(Theme.syne(14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Leave a review

struct LeaveReviewSheet: View {
    let sellerId: String
    let sellerName: String
    let purchases: [ReviewablePurchase]
    let onSubmitted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedProductId: String = ""
    @State private var rating = 0
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var selected: ReviewablePurchase? {
        purchases.first(where: { $0.productId == selectedProductId })
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("review")
                            .font(Theme.syne(34, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(sellerName)
                            .font(Theme.syne(24, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("what did you buy?")
                        ForEach(purchases) { purchase in
                            purchaseRow(purchase)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("rating")
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    Motion.haptic(.light)
                                    rating = star
                                } label: {
                                    Image(systemName: star <= rating ? "star.fill" : "star")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(star <= rating ? .white : campusTheme.textPrimary)
                                        .frame(width: 52, height: 52)
                                        .background(
                                            Circle().fill(star <= rating ? campusTheme.primary : campusTheme.elevatedSurface)
                                        )
                                }
                                .buttonStyle(BouncyButtonStyle(pressedScale: 0.9))
                                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("your review")
                        ZStack(alignment: .topLeading) {
                            if comment.isEmpty {
                                Text("How was the item and the meetup?")
                                    .font(Theme.syne(15))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                            }
                            TextEditor(text: $comment)
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

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text(selected?.existingReview == nil ? "Post review" : "Update review")
                                    .font(Theme.syne(16, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(canSubmit ? campusTheme.primary : campusTheme.textMuted.opacity(0.4))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    .disabled(!canSubmit || isSubmitting)
                }
                .padding(20)
            }
            .background(campusTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(Theme.syne(15, weight: .semibold))
                }
            }
        }
        .onAppear {
            guard selectedProductId.isEmpty else { return }
            let first = purchases.first(where: { $0.existingReview == nil }) ?? purchases.first
            if let first { select(first) }
        }
    }

    private var canSubmit: Bool { selected != nil && rating > 0 }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Theme.syne(18, weight: .semibold))
            .foregroundStyle(campusTheme.textPrimary)
    }

    private func purchaseRow(_ purchase: ReviewablePurchase) -> some View {
        let isSelected = purchase.productId == selectedProductId
        return Button {
            Motion.haptic(.light)
            select(purchase)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: purchase.imageURL ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    campusTheme.elevatedSurface
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(purchase.title)
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(isSelected ? .white : campusTheme.textPrimary)
                        .lineLimit(1)
                    Text(purchase.existingReview == nil ? "Not reviewed yet" : "You reviewed this")
                        .font(Theme.syne(12, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : campusTheme.textMuted)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? .white : campusTheme.textMuted)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? campusTheme.primary : campusTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isSelected ? Color.clear : campusTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    private func select(_ purchase: ReviewablePurchase) {
        selectedProductId = purchase.productId
        rating = purchase.existingReview?.rating ?? 0
        comment = purchase.existingReview?.comment ?? ""
        errorMessage = nil
    }

    private func submit() async {
        guard let selected, rating > 0 else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await FollowReviewService.submitReview(
                sellerId: sellerId,
                productId: selected.productId,
                rating: rating,
                comment: comment
            )
            Motion.haptic(.medium)
            onSubmitted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
