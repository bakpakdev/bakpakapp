import SwiftUI

struct ProductDetailView: View {
    let productId: String
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme
    @Environment(\.dismiss) private var dismiss

    @State private var product: Product?
    @State private var stats = SupabaseListingService.ListingStats()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var imageIndex = 0
    @State private var showDeleteConfirm = false
    @State private var showMarkSoldConfirm = false
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

    var body: some View {
        mainContent
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navTitle }
            .confirmationDialog("Delete this listing?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await deleteListing() } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This can't be undone. Other students will no longer see it.") }
            .confirmationDialog(
                (product?.isSold == true) ? "Mark as available again?" : "Mark as sold?",
                isPresented: $showMarkSoldConfirm, titleVisibility: .visible
            ) {
                Button((product?.isSold == true) ? "Mark available" : "Mark as sold") { Task { await toggleSold() } }
                Button("Cancel", role: .cancel) {}
            }
            .modifier(ProductDetailAlerts(actionError: $actionError, comingSoonMessage: $comingSoonMessage, paymentPresenter: paymentPresenter))
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
                Task {
                    MeetupChecklistStore.completePaid(productId: productId)
                    await load()
                    await refreshActivePayment()
                }
            }
            .task(id: productId) { await pollActivePayment() }
            .campusScreenStyle()
            .task { await load() }
    }

    private var mainContent: some View {
        ZStack {
            campusTheme.background.ignoresSafeArea()
            if let product {
                if isOwner { ownerManageScroll(product) }
                else { buyerScroll(product) }
            } else if isLoading {
                ProgressView().tint(campusTheme.primary)
            } else {
                Text(errorMessage ?? "Listing unavailable")
                    .foregroundStyle(campusTheme.textMuted).padding()
            }
            if isBusy {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var navTitle: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Text("Listing").font(Theme.syne(16, weight: .bold)).foregroundStyle(campusTheme.textPrimary)
        }
    }

    // MARK: - Owner manage layout (Depop-style)

    private func ownerManageScroll(_ product: Product) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ownerHeroSummary(product)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 18)

                statsRow
                    .padding(.top, 4)
                    .padding(.horizontal, 8)

                sectionHeader("Manage listing")
                    .padding(.top, 28)
                    .padding(.horizontal, 16)

                if product.isSold != true {
                    collectPaymentButton(product)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    alternatePaymentAppsRow
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }

                manageList([
                    .init(title: "Send offers", badge: "Recommended", badgeTone: .muted) {
                        comingSoonMessage = "Sending offers is coming soon."
                    },
                    .init(title: "Set discount", badge: nil, badgeTone: .none) {
                        comingSoonMessage = "Discounts are coming soon."
                    },
                    .init(title: "Edit listing", badge: nil, badgeTone: .none) {
                        appState.path.append(.editListing(productId))
                    },
                    .init(title: "Copy listing", badge: nil, badgeTone: .none) {
                        comingSoonMessage = "Copy listing is coming soon."
                    },
                    .init(
                        title: product.isSold == true ? "Mark as available" : "Mark as sold",
                        badge: nil,
                        badgeTone: .none
                    ) {
                        showMarkSoldConfirm = true
                    },
                    .init(title: "Delete", badge: nil, badgeTone: .none, destructive: true) {
                        showDeleteConfirm = true
                    },
                ])

                Spacer(minLength: 40)
            }
            .padding(.bottom, 24)
        }
        .background(campusTheme.background)
    }

    private func ownerHeroSummary(_ product: Product) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: imageURLs.first ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    campusTheme.elevatedSurface
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(Theme.syne(16, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(2)
                Text("$\(formattedPrice(product.price))")
                    .font(Theme.syne(18, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
                if product.isSold == true {
                    Text("Sold")
                        .font(Theme.syne(11, weight: .bold))
                        .foregroundStyle(campusTheme.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 0) {
            statCell(icon: "percent", value: "\(stats.offers)", label: "Offers")
            statCell(icon: "heart", value: "\(stats.likes)", label: "Likes")
            statCell(
                icon: "eye",
                value: stats.views.map(String.init) ?? "–",
                label: "Views",
                boostHint: stats.views == nil
            )
        }
    }

    private func statCell(icon: String, value: String, label: String, boostHint: Bool = false) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            Text(value)
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(label)
                .font(Theme.syne(11, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
            if boostHint {
                Button {
                    comingSoonMessage = "Boosting isn’t available yet."
                } label: {
                    Text("Boost to see")
                        .font(Theme.syne(9, weight: .semibold))
                        .foregroundStyle(campusTheme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(campusTheme.elevatedSurface)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(height: 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.syne(20, weight: .bold))
            .foregroundStyle(campusTheme.textPrimary)
            .padding(.bottom, 6)
    }

    private struct ManageRowModel {
        let title: String
        let badge: String?
        enum BadgeTone { case none, muted, accent }
        let badgeTone: BadgeTone
        var destructive: Bool = false
        let action: () -> Void
    }

    private func manageList(_ rows: [ManageRowModel]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Button(action: row.action) {
                    HStack(spacing: 10) {
                        Text(row.title)
                            .font(Theme.syne(16, weight: .regular))
                            .foregroundStyle(row.destructive ? Color(hex: "#FF6B6B") : campusTheme.textPrimary)
                        Spacer(minLength: 8)
                        if let badge = row.badge {
                            Text(badge)
                                .font(Theme.syne(11, weight: .semibold))
                                .foregroundStyle(row.badgeTone == .accent ? campusTheme.primary : campusTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    row.badgeTone == .accent
                                        ? campusTheme.primary.opacity(0.15)
                                        : campusTheme.elevatedSurface
                                )
                                .clipShape(Capsule())
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(campusTheme.textMuted.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < rows.count - 1 {
                    Divider()
                        .overlay(campusTheme.border)
                        .padding(.leading, 16)
                }
            }
        }
    }

    // MARK: - Buyer product layout

    private func buyerScroll(_ product: Product) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    imageHero
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("$\(formattedPrice(product.price))")
                                .font(Theme.syne(28, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                            Text(product.title)
                                .font(Theme.syne(22, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                        }
                        metaChips(product)
                        descriptionBlock(product)
                        sellerCard(product)
                    }
                    .padding(16)
                    .padding(.bottom, 100)
                }
            }

            buyerBottomBar(product)
        }
    }

    private var imageHero: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottom) {
                Group {
                    if imageURLs.isEmpty {
                        campusTheme.elevatedSurface
                    } else {
                        TabView(selection: $imageIndex) {
                            ForEach(Array(imageURLs.enumerated()), id: \.offset) { idx, url in
                                AsyncImage(url: URL(string: url)) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    default:
                                        campusTheme.elevatedSurface
                                    }
                                }
                                .tag(idx)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipped()

                if imageURLs.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<imageURLs.count, id: \.self) { idx in
                            Capsule()
                                .fill(idx == imageIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: idx == imageIndex ? 16 : 6, height: 6)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }

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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(campusTheme.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(campusTheme.border, lineWidth: 1))
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
            Text(desc.isEmpty || desc == " " ? "No description provided." : desc)
                .font(.system(size: 15))
                .foregroundStyle(campusTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(campusTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                ZStack {
                    AsyncImage(url: URL(string: seller?.avatar ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                    Text("View profile")
                        .font(.system(size: 12))
                        .foregroundStyle(campusTheme.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(14)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    appState.path.append(.conversation("", userId, product.id))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Message seller")
                            .font(.system(size: 14, weight: .bold))
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
                        Text("Send offer")
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(campusTheme.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(campusTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(campusTheme.primary.opacity(0.35), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(campusTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(campusTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
                .disabled(isPaymentBusy)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            } else if activePayment?.active == true, activePayment?.role == "buyer" {
                Text("Seller is ready to collect payment")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
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
                            .font(.system(size: 13, weight: .medium))
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
                                    .font(.system(size: 13, weight: .semibold))
                                    .opacity(0.85)
                            }
                            .foregroundStyle(selected ? Color.white : campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selected ? campusTheme.primary : campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(selected ? Color.clear : campusTheme.border, lineWidth: 1)
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
                            if !newValue.isEmpty {
                                selectedOfferPercent = nil
                            } else if selectedOfferPercent == nil {
                                selectedOfferPercent = 15
                            }
                        }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(campusTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            customOfferText.isEmpty ? campusTheme.border : campusTheme.primary.opacity(0.35),
                            lineWidth: 1
                        )
                )

                if let offerAmount, offerAmount > 0 {
                    let savings = max(0, listed - offerAmount)
                    HStack {
                        Text("Your offer")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                        Spacer()
                        Text("$\(offerAmount, specifier: "%.2f")")
                            .font(Theme.syne(18, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                        if savings > 0.5 {
                            Text("· $\(savings, specifier: "%.0f") off")
                                .font(.system(size: 12, weight: .semibold))
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
                                .font(.system(size: 15, weight: .bold))
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
        .background(campusTheme.surface)
        .presentationDetents([.height(520)])
        .presentationDragIndicator(.hidden)
        .environment(\.campusTheme, campusTheme)
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
            let convo = try await messageService.openOrCreate(otherUserId: sellerId, productId: product.id)
            _ = try await messageService.send(
                conversationId: convo.id,
                content: "💰 Offer: $\(formatted)"
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
            HStack(spacing: 10) {
                Image(systemName: "wave.3.right.circle.fill")
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Collect payment")
                        .font(.system(size: 15, weight: .bold))
                    Text("Buyer taps their card or phone on yours")
                        .font(.system(size: 12))
                        .opacity(0.85)
                }
                Spacer()
                if isPaymentBusy {
                    ProgressView().tint(.white)
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(campusTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
        .disabled(isPaymentBusy || product.isSold == true)
    }

    private var alternatePaymentAppsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or pay with")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
                .padding(.leading, 2)

            HStack(spacing: 8) {
                paymentAppButton(
                    title: "Venmo",
                    logo: "venmo_logo",
                    tint: Color(hex: "#008CFF"),
                    appSchemes: ["venmo://"],
                    webFallback: ExternalPaymentApps.venmoAppStore
                )
                paymentAppButton(
                    title: "Cash App",
                    logo: "cashapp_logo",
                    tint: Color(hex: "#00D632"),
                    appSchemes: ["cashapp://", "squarecash://"],
                    webFallback: ExternalPaymentApps.cashAppAppStore
                )
                paymentAppButton(
                    title: "PayPal",
                    logo: "paypal_logo",
                    tint: Color(hex: "#0070BA"),
                    appSchemes: ["paypal://"],
                    webFallback: ExternalPaymentApps.paypalWeb
                )
            }
        }
    }

    private func paymentAppButton(
        title: String,
        logo: String,
        tint: Color,
        appSchemes: [String],
        webFallback: String
    ) -> some View {
        Button {
            openExternalPaymentApp(schemes: appSchemes, webFallback: webFallback)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint)
                Image(logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
        .accessibilityLabel(title)
    }

    private func openExternalPaymentApp(schemes: [String], webFallback: String) {
        Motion.haptic(.light)
        ExternalPaymentApps.open(schemes: schemes, fallbackURL: webFallback)
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
                    .font(.system(size: 15))
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
                            .font(.system(size: 15, weight: .bold))
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
                            .font(.system(size: 15, weight: .semibold))
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
                        MeetupChecklistStore.completePaid(productId: productId)
                        await load()
                    }
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
        let wasLiked = isLiked
        await MainActor.run { isLiked = !wasLiked }
        do {
            if wasLiked {
                try await socialService.unlike(productId: productId)
            } else {
                try await socialService.like(productId: productId)
            }
            stats = await productService.listingStats(id: productId)
        } catch {
            await MainActor.run { isLiked = wasLiked }
            actionError = error.localizedDescription
        }
    }

    private func toggleSave() async {
        let wasSaved = isSaved
        await MainActor.run { isSaved = !wasSaved }
        do {
            if wasSaved {
                try await socialService.unsave(productId: productId)
            } else {
                try await socialService.save(productId: productId)
            }
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

    func body(content: Content) -> some View {
        content
            .alert("Couldn't update", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
                Button("OK", role: .cancel) { actionError = nil }
            } message: { Text(actionError ?? "") }
            .alert("Coming soon", isPresented: Binding(get: { comingSoonMessage != nil }, set: { if !$0 { comingSoonMessage = nil } })) {
                Button("OK", role: .cancel) { comingSoonMessage = nil }
            } message: { Text(comingSoonMessage ?? "") }
            .alert("Payment", isPresented: Binding(get: { paymentPresenter.errorMessage != nil }, set: { if !$0 { paymentPresenter.errorMessage = nil } })) {
                Button("OK", role: .cancel) { paymentPresenter.errorMessage = nil }
            } message: { Text(paymentPresenter.errorMessage ?? "") }
    }
}
