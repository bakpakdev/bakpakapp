import SwiftUI

struct ProductDetailView: View {
    let productId: String
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var stats = SupabaseListingService.ListingStats()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var imageIndex = 0
    @State private var showDeleteConfirm = false
    @State private var showMarkSoldConfirm = false
    @State private var showCopyConfirm = false
    @State private var isBusy = false
    @State private var actionError: String?
    @State private var comingSoonMessage: String?
    @StateObject private var paymentPresenter = PaymentSheetPresenter()
    @StateObject private var tapToPay = TapToPayCollector()
    @State private var activePayment: ActiveMeetupPaymentResponse?
    @State private var sellerWaitingRequestId: String?
    @State private var showSellerPaymentSheet = false
    @State private var isPaymentBusy = false
    @State private var lastMeetupPayment: CreateMeetupPaymentResponse?
    @State private var showOfferSheet = false
    @State private var selectedOfferPercent: Int? = 15
    @State private var customOfferText = ""
    @State private var isSendingOffer = false
    @State private var isLiked = false
    @State private var isSaved = false
    @State private var reactionBusy = false
    @State private var sellerRating: ReviewSummary?
    @State private var paymentOutcome: PaymentOutcomeKind?

    private let productService = ProductService()
    private let socialService = SocialService()
    private let paymentService = MeetupPaymentService.shared
    private let messageService = MessageService()
    private let offerPercents = [10, 15, 20, 25]

    private var isOwner: Bool {
        guard let mine = authVM.user?.id.lowercased(),
              let seller = product?.user?.id.lowercased() else { return false }
        return mine == seller
    }

    private var imageURLs: [String] {
        let imgs = product?.images ?? []
        let sorted = imgs.sorted { ($0.isPrimary == true ? 0 : 1) < ($1.isPrimary == true ? 0 : 1) }
        return sorted.compactMap(\.url).filter { !$0.isEmpty }
    }

    private var isShowingConfirm: Bool {
        showDeleteConfirm || showMarkSoldConfirm || showCopyConfirm
    }

    var body: some View {
        mainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isOwner { navTitle }
            }
            .overlay { confirmCards }
            .modifier(ProductDetailAlerts(actionError: $actionError, comingSoonMessage: $comingSoonMessage, paymentPresenter: paymentPresenter, suppressPaymentAlert: paymentOutcome != nil))
            .sheet(isPresented: $showSellerPaymentSheet) { sellerPaymentWaitingSheet }
            .sheet(isPresented: $showOfferSheet) {
                if let product {
                    sendOfferPopup(product)
                }
            }
            .background(PaymentSheetHost(presenter: paymentPresenter))
            .onChange(of: paymentPresenter.didComplete) { completed in
                guard completed else { return }
                paymentPresenter.didComplete = false
                presentPaymentOutcome(.success)
                Task {
                    await meetupStore.markCompleted(productId: productId)
                    await load()
                    await refreshActivePayment()
                }
            }
            .onChange(of: paymentPresenter.errorMessage) { message in
                guard message != nil, paymentOutcome == nil else { return }
                presentPaymentOutcome(.failure)
            }
            .task(id: productId) { await pollActivePayment() }
            .campusPageStyle()
            .overlay {
                if let paymentOutcome {
                    PaymentOutcomeOverlay(
                        kind: paymentOutcome,
                        isCollecting: isOwner,
                        onContinue: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                self.paymentOutcome = nil
                            }
                        }
                    )
                    .ignoresSafeArea()
                    .transition(.opacity)
                }
            }
            .toolbar(paymentOutcome == nil && !isShowingConfirm ? .visible : .hidden, for: .navigationBar)
            .hidesSystemNavigationBar(paymentOutcome != nil || isShowingConfirm)
            .onChange(of: paymentOutcome) { value in
                appState.hidesTabBar = value != nil || isShowingConfirm
            }
            .onChange(of: isShowingConfirm) { showing in
                appState.hidesTabBar = showing || paymentOutcome != nil
            }
            // onAppear (not .task) so the screen refreshes after Edit / Discount / Offers pop back.
            .onAppear { Task { await load() } }
    }

    /// In-app confirm cards (replace system confirmation dialogs).
    @ViewBuilder
    private var confirmCards: some View {
        if showDeleteConfirm {
            ConfirmActionCard(
                title: "delete listing?",
                message: "This can’t be undone. Other students will no longer see it.",
                confirmTitle: "Delete",
                confirmIcon: "trash",
                onConfirm: {
                    showDeleteConfirm = false
                    Task { await deleteListing() }
                },
                onCancel: { showDeleteConfirm = false }
            )
            .ignoresSafeArea()
            .zIndex(10)
        } else if showMarkSoldConfirm {
            let sold = product?.isSold == true
            ConfirmActionCard(
                title: sold ? "mark as available?" : "mark as sold?",
                message: sold
                    ? "It’ll show up on the Grid again and buyers can message you about it."
                    : "Use this if you sold it for cash or outside the app. It won’t add to your balance.",
                confirmTitle: sold ? "Mark available" : "Mark as sold",
                confirmIcon: sold ? "arrow.uturn.backward" : "checkmark.seal",
                tone: .primary,
                onConfirm: {
                    showMarkSoldConfirm = false
                    Task { await toggleSold() }
                },
                onCancel: { showMarkSoldConfirm = false }
            )
            .ignoresSafeArea()
            .zIndex(10)
        } else if showCopyConfirm {
            ConfirmActionCard(
                title: "copy listing?",
                message: "A new live listing with the same photos and details will be created. You can edit it right after.",
                confirmTitle: "Copy listing",
                confirmIcon: "doc.on.doc",
                tone: .primary,
                onConfirm: {
                    showCopyConfirm = false
                    Task { await copyListing() }
                },
                onCancel: { showCopyConfirm = false }
            )
            .ignoresSafeArea()
            .zIndex(10)
        }
    }

    private var cardStroke: Color {
        campusTheme.isDark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)
    }

    private var glassFill: Color {
        Color.white.opacity(campusTheme.isDark ? 0.06 : 0.55)
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            if let product {
                if isOwner { ownerManageScroll(product) }
                else { buyerScroll(product) }
            } else if isLoading {
                ProgressView().tint(campusTheme.primary)
            } else {
                Text(errorMessage ?? "Listing unavailable")
                    .font(Theme.syne(15, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .padding()
            }

            if isBusy {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var navTitle: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Listing").font(Theme.syne(16, weight: .bold)).foregroundStyle(campusTheme.textPrimary)
        }
    }

    // MARK: - Owner manage layout (matches the settings / campus page chrome)

    private func ownerManageScroll(_ product: Product) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                CampusPageHeader(
                    title: "listing",
                    subtitle: product.isSold == true ? "sold" : "manage & sell"
                )

                ownerHeroSummary(product)

                statsCard

                if product.isSold != true {
                    collectPaymentButton(product)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SettingsSectionTitle(title: "sell faster")
                    VStack(spacing: 0) {
                        SettingsNavRow(
                            icon: "tag",
                            title: "Send offers",
                            subtitle: offersSubtitle
                        ) {
                            appState.path.append(.sendOffers(productId))
                        }
                        SettingsNavRow(
                            icon: "percent",
                            title: product.hasDiscount ? "Change discount" : "Set discount",
                            subtitle: discountSubtitle(product),
                            showDivider: false
                        ) {
                            appState.path.append(.setDiscount(productId))
                        }
                    }
                    .background(CampusCardBackground())
                }

                VStack(alignment: .leading, spacing: 0) {
                    SettingsSectionTitle(title: "listing")
                    VStack(spacing: 0) {
                        SettingsNavRow(
                            icon: "square.and.pencil",
                            title: "Edit listing",
                            subtitle: "Title, description, brand, size"
                        ) {
                            appState.path.append(.editListing(productId))
                        }
                        SettingsNavRow(
                            icon: "doc.on.doc",
                            title: "Copy listing",
                            subtitle: "Relist the same item in one tap"
                        ) {
                            showCopyConfirm = true
                        }
                        SettingsNavRow(
                            icon: product.isSold == true ? "arrow.uturn.backward" : "checkmark.seal",
                            title: product.isSold == true ? "Mark as available" : "Mark as sold",
                            subtitle: product.isSold == true
                                ? "Put it back on the Grid"
                                : "Sold for cash or outside the app",
                            showDivider: false
                        ) {
                            showMarkSoldConfirm = true
                        }
                    }
                    .background(CampusCardBackground())
                }

                deleteButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private var offersSubtitle: String {
        if stats.likes == 0 { return "Message everyone who’s interested" }
        return stats.likes == 1 ? "1 person liked this" : "\(stats.likes) people liked this"
    }

    private func discountSubtitle(_ product: Product) -> String {
        if let pct = product.discountPercent, let original = product.originalPrice {
            return "\(pct)% off · was $\(formattedPrice(original))"
        }
        return "Lower the price and show the savings"
    }

    private func ownerHeroSummary(_ product: Product) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: imageURLs.first ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    campusTheme.elevatedSurface
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(campusTheme.textMuted)
                        }
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(product.title)
                    .font(Theme.syne(17, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(formattedPrice(product.price))")
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    if product.hasDiscount, let original = product.originalPrice {
                        Text("$\(formattedPrice(original))")
                            .font(Theme.syne(14, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted)
                            .strikethrough()
                    }
                }
                HStack(spacing: 6) {
                    statusChip(
                        product.isSold == true ? "Sold" : "Live",
                        tint: product.isSold == true ? campusTheme.textMuted : campusTheme.primary
                    )
                    if let pct = product.discountPercent {
                        statusChip("\(pct)% off", tint: campusTheme.primary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CampusCardBackground())
    }

    private func statusChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.syne(11, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statsCard: some View {
        HStack(alignment: .top, spacing: 0) {
            statCell(icon: "percent", value: "\(stats.offers)", label: "Offers")
            statDivider
            statCell(icon: "heart", value: "\(stats.likes)", label: "Likes")
            statDivider
            statCell(icon: "eye", value: stats.views.map(String.init) ?? "–", label: "Views")
        }
        .padding(.vertical, 18)
        .background(CampusCardBackground())
    }

    private var statDivider: some View {
        Rectangle()
            .fill(campusTheme.border)
            .frame(width: 1, height: 44)
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 34, height: 34)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(value)
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(label)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var deleteButton: some View {
        Button {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                Text("Delete listing")
                    .font(Theme.syne(15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "#E11D48"))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(campusTheme.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: "#E11D48").opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        .padding(.top, 4)
    }

    // MARK: - Buyer product layout

    private func buyerScroll(_ product: Product) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    imageHero

                    VStack(alignment: .leading, spacing: 8) {
                        if let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
                            Text(brand.uppercased())
                                .font(Theme.syne(11, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(campusTheme.textMuted)
                        }
                        Text(product.title)
                            .font(Theme.syne(24, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("$\(formattedPrice(product.price))")
                                .font(Theme.syne(26, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                            if product.hasDiscount, let original = product.originalPrice {
                                Text("$\(formattedPrice(original))")
                                    .font(Theme.syne(16, weight: .semibold))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .strikethrough()
                                if let pct = product.discountPercent {
                                    Text("\(pct)% off")
                                        .font(Theme.syne(11, weight: .bold))
                                        .foregroundStyle(campusTheme.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(campusTheme.primary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    metaChips(product)
                    descriptionBlock(product)
                    sellerCard(product)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 120)
            }

            buyerBottomBar(product)
        }
    }

    private var imageHero: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottom) {
                Group {
                    if imageURLs.isEmpty {
                        Color.white.opacity(0.08)
                    } else {
                        TabView(selection: $imageIndex) {
                            ForEach(Array(imageURLs.enumerated()), id: \.offset) { idx, url in
                                AsyncImage(url: URL(string: url)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        Color.white.opacity(0.08)
                                    }
                                }
                                .tag(idx)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(0.92, contentMode: .fit)
                .clipped()

                if imageURLs.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<imageURLs.count, id: \.self) { idx in
                            Capsule()
                                .fill(idx == imageIndex ? Color.white : Color.white.opacity(0.45))
                                .frame(width: idx == imageIndex ? 16 : 6, height: 6)
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )

            if !isOwner {
                ListingReactionButtons(
                    isLiked: isLiked,
                    isSaved: isSaved,
                    compact: false,
                    onLike: { Task { await toggleLike() } },
                    onSave: { Task { await toggleSave() } }
                )
                .padding(14)
            }
        }
    }

    private func metaChips(_ product: Product) -> some View {
        let chips = metaChipValues(product)
        return Group {
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(Theme.syne(12, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(glassFill)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(cardStroke, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private func descriptionBlock(_ product: Product) -> some View {
        let desc = (product.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(Theme.syne(15, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(desc.isEmpty || desc == " " ? "No description provided." : desc)
                .font(Theme.syne(15))
                .foregroundStyle(campusTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private func sellerCard(_ product: Product) -> some View {
        let seller = product.user
        let name: String = {
            if let s = seller?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
            return seller?.username ?? "Seller"
        }()
        return Button {
            if let userId = seller?.id {
                appState.path.append(.userProfile(userId))
            }
        } label: {
            HStack(spacing: 12) {
                AvatarView(urlString: seller?.avatar, size: 48, initials: name)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(Theme.syne(15, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                    if let sellerRating, sellerRating.count > 0 {
                        HStack(spacing: 6) {
                            ReviewStars(rating: sellerRating.average, size: 11)
                            Text(String(format: "%.1f · %d", sellerRating.average, sellerRating.count))
                                .font(Theme.syne(12, weight: .medium))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                    } else {
                        Text("View profile")
                            .font(Theme.syne(12, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(14)
            .background(glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }

    @ViewBuilder
    private func buyerBottomBar(_ product: Product) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Motion.haptic(.medium)
                    guard let userId = product.user?.id else { return }
                    Task { await startMessage(for: product, sellerId: userId) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Message")
                            .font(Theme.syne(14, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(campusTheme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))

                Button {
                    Motion.haptic(.light)
                    selectedOfferPercent = 15
                    customOfferText = ""
                    showOfferSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Offer")
                            .font(Theme.syne(14, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(glassFill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(campusTheme.primary.opacity(0.45), lineWidth: 1.5)
                    )
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(product.isSold == true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, activePayment?.canPay == true ? 8 : 10)

            if activePayment?.canPay == true, product.isSold != true {
                Button {
                    Task { await startBuyerPayment() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo")
                        Text("Pay with Apple Pay")
                    }
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(glassFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(cardStroke, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(isPaymentBusy)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            } else if activePayment?.active == true, activePayment?.role == "buyer" {
                Text("Seller is ready to collect payment")
                    .font(Theme.syne(13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .padding(.top, 10)
        .background(
            campusTheme.background.opacity(0.92)
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func sendOfferPopup(_ product: Product) -> some View {
        let listed = product.price
        let customAmount = Double(customOfferText.replacingOccurrences(of: ",", with: ""))
        let percentAmount: Double? = selectedOfferPercent.map { listed * (1.0 - Double($0) / 100.0) }
        let offerAmount = customAmount ?? percentAmount
        let canSend = (offerAmount ?? 0) > 0 && (offerAmount ?? 0) <= listed + 0.001

        return VStack(spacing: 0) {
            Capsule()
                .fill(campusTheme.border)
                .frame(width: 40, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    AsyncImage(url: URL(string: product.images?.first(where: { $0.isPrimary == true })?.url
                                        ?? product.images?.first?.url
                                        ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        campusTheme.elevatedSurface
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Send an offer")
                            .font(Theme.syne(18, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                        Text(product.title)
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                            .lineLimit(1)
                        Text("Listed at $\(Int(listed))")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        showOfferSheet = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }

                Text("Quick offers")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(offerPercents, id: \.self) { percent in
                        let amount = listed * (1.0 - Double(percent) / 100.0)
                        let selected = selectedOfferPercent == percent && customOfferText.isEmpty
                        Button {
                            Motion.haptic(.light)
                            selectedOfferPercent = percent
                            customOfferText = ""
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(percent)% off")
                                    .font(Theme.syne(14, weight: .bold))
                                Text("$\(amount, specifier: "%.0f")")
                                    .font(Theme.syne(13, weight: .semibold))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selected ? campusTheme.primary : glassFill)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? Color.clear : cardStroke, lineWidth: 1)
                            )
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                    }
                }

                Text("Or enter a custom amount")
                    .font(Theme.syne(13, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)

                HStack(spacing: 8) {
                    Text("$")
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    TextField("Custom offer", text: $customOfferText)
                        .keyboardType(.decimalPad)
                        .font(Theme.syne(22, weight: .bold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .onChange(of: customOfferText) { newValue in
                            let cleaned = MoneyAmount.sanitized(newValue)
                            if cleaned != newValue { customOfferText = cleaned }
                            if !cleaned.isEmpty {
                                selectedOfferPercent = nil
                            } else if selectedOfferPercent == nil {
                                selectedOfferPercent = 15
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            customOfferText.isEmpty ? cardStroke : campusTheme.primary.opacity(0.35),
                            lineWidth: 1
                        )
                )

                if let offerAmount, offerAmount > 0 {
                    let savings = max(0, listed - offerAmount)
                    HStack {
                        Text("Your offer")
                            .font(Theme.syne(13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                        Spacer()
                        Text("$\(offerAmount, specifier: "%.2f")")
                            .font(Theme.syne(18, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                        if savings > 0.5 {
                            Text("· $\(savings, specifier: "%.0f") off")
                                .font(Theme.syne(12, weight: .semibold))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                    }
                    .padding(.top, 2)
                }

                Button {
                    guard let offerAmount, let userId = product.user?.id else { return }
                    Task { await sendOffer(amount: offerAmount, sellerId: userId, product: product) }
                } label: {
                    HStack(spacing: 8) {
                        if isSendingOffer {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Send offer")
                                .font(Theme.syne(15, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSend && !isSendingOffer ? campusTheme.primary : campusTheme.primary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(!canSend || isSendingOffer)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(campusTheme.background)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.hidden)
        .environment(\.campusTheme, campusTheme)
    }

    private func startMessage(for product: Product, sellerId: String) async {
        do {
            let convo = try await messageService.openOrCreate(otherUserId: sellerId, productId: product.id)
            appState.path.append(.conversation(convo.id, sellerId, product.id))
        } catch {
            // Still open the chat; ConversationView will create/reuse the thread.
            appState.path.append(.conversation("", sellerId, product.id))
        }
    }

    private func sendOffer(amount: Double, sellerId: String, product: Product) async {
        isSendingOffer = true
        defer { isSendingOffer = false }
        do {
            let formatted: String = {
                if amount.rounded() == amount {
                    return String(format: "%.0f", amount)
                }
                return String(format: "%.2f", amount)
            }()
            let imageURL = product.images?.first(where: { $0.isPrimary == true })?.url
                ?? product.images?.first?.url
            let convo = try await messageService.openOrCreate(otherUserId: sellerId, productId: product.id)
            _ = try await messageService.send(
                conversationId: convo.id,
                content: OfferMessageCodec.encode(
                    amount: formatted,
                    productId: product.id,
                    title: product.title,
                    price: product.price,
                    imageURL: imageURL
                )
            )
            showOfferSheet = false
            Motion.haptic(.medium)
            appState.path.append(.conversation(convo.id, sellerId, product.id))
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Meetup payments

    private func collectPaymentButton(_ product: Product) -> some View {
        Button {
            Task { await startSellerPayment() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Collect payment")
                        .font(Theme.syne(15, weight: .bold))
                    Text("Buyer taps their card or phone on yours")
                        .font(Theme.syne(12, weight: .medium))
                        .opacity(0.85)
                }
                Spacer()
                if isPaymentBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(campusTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
        .disabled(isPaymentBusy || product.isSold == true)
    }

    private func copyListing() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let copy = try await productService.duplicateListing(id: productId)
            Motion.haptic(.medium)
            appState.path.append(.editListing(copy.id))
        } catch {
            actionError = error.localizedDescription
        }
    }

    private var sellerPaymentWaitingSheet: some View {
        NavigationStack {
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .fill(campusTheme.primary.opacity(0.12))
                        .frame(width: 120, height: 120)
                    Image(systemName: tapPhaseIcon)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                }
                .padding(.top, 20)

                Text(tapPhaseTitle)
                    .font(Theme.syne(24, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(tapToPay.statusMessage)
                    .font(Theme.syne(15))
                    .foregroundStyle(campusTheme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                if let product {
                    Text("$\(formattedPrice(product.price))")
                        .font(Theme.syne(32, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }

                Spacer()

                if case .failed = tapToPay.phase {
                    Button {
                        Task { await retryTapToPay() }
                    } label: {
                        Text("Try again")
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(campusTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                }

                if let requestId = sellerWaitingRequestId, tapToPay.phase != .succeeded {
                    Button(role: .destructive) {
                        tapToPay.cancel()
                        Task { await cancelSellerPayment(requestId: requestId) }
                    } label: {
                        Text("Cancel")
                            .font(Theme.syne(15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .navigationTitle("Tap to Pay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if tapToPay.phase != .succeeded {
                            tapToPay.cancel()
                        }
                        showSellerPaymentSheet = false
                    }
                }
            }
            .campusScreenStyle()
            .onChange(of: tapToPay.phase) { phase in
                if phase == .succeeded {
                    Task {
                        if let requestId = sellerWaitingRequestId {
                            try? await paymentService.confirm(
                                requestId: requestId,
                                squarePaymentId: tapToPay.lastSquarePaymentId
                            )
                        }
                        await meetupStore.markCompleted(productId: productId)
                        showSellerPaymentSheet = false
                        presentPaymentOutcome(.success)
                        await load()
                    }
                } else if case .failed = phase {
                    showSellerPaymentSheet = false
                    presentPaymentOutcome(.failure)
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(tapToPay.phase == .readyForTap || tapToPay.phase == .processing)
    }

    private var tapPhaseIcon: String {
        switch tapToPay.phase {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .readyForTap: return "wave.3.right.circle.fill"
        default: return "iphone.radiowaves.left.and.right"
        }
    }

    private var tapPhaseTitle: String {
        switch tapToPay.phase {
        case .succeeded: return "Paid"
        case .failed: return "Couldn’t collect"
        case .readyForTap: return "Ready for tap"
        case .processing: return "Processing"
        case .connecting, .preparing: return "Getting ready"
        case .idle: return "Tap to Pay"
        }
    }

    private func presentPaymentOutcome(_ kind: PaymentOutcomeKind) {
        if kind == .failure {
            paymentPresenter.errorMessage = nil
        }
        withAnimation(.easeInOut(duration: 0.25)) {
            paymentOutcome = kind
        }
    }

    private func pollActivePayment() async {
        while !Task.isCancelled {
            await refreshActivePayment()
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func refreshActivePayment() async {
        guard SquareConfig.isConfigured || !SquareConfig.apiBaseURL.isEmpty else { return }
        do {
            let active = try await paymentService.fetchActive(productId: productId)
            activePayment = active
            if active.status == "paid" || active.active == false {
                if showSellerPaymentSheet { showSellerPaymentSheet = false }
                if product?.isSold != true {
                    product = try? await productService.product(id: productId)
                }
            }
        } catch {
            // Payment API may be offline during dev; ignore polling errors.
        }
    }

    private func startSellerPayment() async {
        if let blocker = SquareConfig.userFacingBlocker {
            actionError = blocker
            return
        }
        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            let response = try await paymentService.createRequest(productId: productId)
            sellerWaitingRequestId = response.paymentRequest.id
            lastMeetupPayment = response
            showSellerPaymentSheet = true
            Motion.haptic(.medium)
            tapToPay.start(from: response)
            await refreshActivePayment()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func retryTapToPay() async {
        if let lastMeetupPayment {
            tapToPay.start(from: lastMeetupPayment)
            return
        }
        await startSellerPayment()
    }

    private func startBuyerPayment() async {
        if let blocker = SquareConfig.userFacingBlocker {
            actionError = blocker
            return
        }
        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            let requestId: String
            if let existing = activePayment?.paymentRequestId, activePayment?.canPay == true {
                requestId = existing
            } else {
                let created = try await paymentService.createRequest(productId: productId)
                requestId = created.paymentRequest.id
                await refreshActivePayment()
            }
            let checkout = try await paymentService.fetchCheckout(requestId: requestId)
            paymentPresenter.prepareAndPresent(checkout: checkout)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func cancelSellerPayment(requestId: String) async {
        isPaymentBusy = true
        defer { isPaymentBusy = false }
        do {
            try await paymentService.cancel(requestId: requestId)
            sellerWaitingRequestId = nil
            showSellerPaymentSheet = false
            await refreshActivePayment()
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func metaChipValues(_ product: Product) -> [String] {
        var chips: [String] = []
        if let brand = product.brand?.trimmingCharacters(in: .whitespacesAndNewlines), !brand.isEmpty {
            chips.append(brand)
        }
        if let condition = product.condition?.trimmingCharacters(in: .whitespacesAndNewlines), !condition.isEmpty {
            chips.append(condition.replacingOccurrences(of: "-", with: " ").capitalized)
        }
        if let category = product.category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            chips.append(category.capitalized)
        }
        return chips
    }

    private func formattedPrice(_ price: Double) -> String {
        price.rounded() == price ? String(Int(price)) : String(format: "%.2f", price)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            product = try await productService.product(id: productId)
            stats = await productService.listingStats(id: productId)
            await loadReactions()
            if let sellerId = product?.user?.id,
               let reviews = try? await FollowReviewService.reviews(sellerId: sellerId) {
                sellerRating = ReviewSummary(reviews: reviews)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadReactions() async {
        guard authVM.user != nil else { return }
        // Wait until product is set so isOwner is accurate.
        if isOwner {
            await MainActor.run {
                isLiked = false
                isSaved = false
            }
            return
        }
        guard let client = await SupabaseManager.shared.clientWithValidSession(),
              SupabaseConfig.isConfigured else {
            // REST fallback: scan lists
            async let likedTask = socialService.likedItems()
            async let savedTask = socialService.savedItems()
            do {
                let (liked, saved) = try await (likedTask, savedTask)
                let pid = productId.lowercased()
                await MainActor.run {
                    isLiked = liked.contains { $0.id.lowercased() == pid }
                    isSaved = saved.contains { $0.id.lowercased() == pid }
                }
            } catch {}
            return
        }
        do {
            async let liked = SupabaseSocialService.isLiked(client: client, productId: productId)
            async let saved = SupabaseSocialService.isSaved(client: client, productId: productId)
            let (l, s) = try await (liked, saved)
            await MainActor.run {
                isLiked = l
                isSaved = s
            }
        } catch {}
    }

    private func toggleLike() async {
        guard !reactionBusy else { return }
        reactionBusy = true
        defer { reactionBusy = false }
        let wasLiked = isLiked
        await MainActor.run { isLiked = !wasLiked }
        do {
            try await socialService.setLiked(productId: productId, liked: !wasLiked)
            stats = await productService.listingStats(id: productId)
        } catch {
            await MainActor.run { isLiked = wasLiked }
            actionError = error.localizedDescription
        }
    }

    private func toggleSave() async {
        guard !reactionBusy else { return }
        reactionBusy = true
        defer { reactionBusy = false }
        let wasSaved = isSaved
        await MainActor.run { isSaved = !wasSaved }
        do {
            try await socialService.setSaved(productId: productId, saved: !wasSaved)
        } catch {
            await MainActor.run { isSaved = wasSaved }
            actionError = error.localizedDescription
        }
    }

    private func deleteListing() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await productService.deleteProduct(id: productId)
            Motion.haptic(.medium)
            if !appState.path.isEmpty { appState.path.removeLast() } else { dismiss() }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleSold() async {
        guard let product else { return }
        isBusy = true
        defer { isBusy = false }
        let next = !(product.isSold == true)
        do {
            // Manual sold = sold outside Square — no balance credit.
            if next, let requestId = activePayment?.paymentRequestId ?? sellerWaitingRequestId {
                tapToPay.cancel()
                try? await paymentService.cancel(requestId: requestId)
                sellerWaitingRequestId = nil
                showSellerPaymentSheet = false
                activePayment = nil
            }
            try await productService.setSold(id: productId, isSold: next)
            self.product = try await productService.product(id: productId)
            Motion.haptic(.light)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct ProductDetailAlerts: ViewModifier {
    @Binding var actionError: String?
    @Binding var comingSoonMessage: String?
    @ObservedObject var paymentPresenter: PaymentSheetPresenter
    var suppressPaymentAlert: Bool = false

    func body(content: Content) -> some View {
        content
            .alert("Couldn't update", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: { Text(actionError ?? "") }
            .alert("Coming soon", isPresented: Binding(get: { comingSoonMessage != nil }, set: { if !$0 { comingSoonMessage = nil } })) {
                Button("OK", role: .cancel) { comingSoonMessage = nil }
            } message: { Text(comingSoonMessage ?? "") }
            .alert("Payment", isPresented: Binding(get: { !suppressPaymentAlert && paymentPresenter.errorMessage != nil }, set: { if !$0 { paymentPresenter.errorMessage = nil } })) {
                Button("OK", role: .cancel) { paymentPresenter.errorMessage = nil }
            } message: { Text(paymentPresenter.errorMessage ?? "") }
    }
}
