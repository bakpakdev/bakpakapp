import SwiftUI
import UIKit

// MARK: - UI models (mapped from `Conversation` / `Message`)

private struct ChatParticipant {
    let id: String
    let name: String
    let avatar: String
    let isOnline: Bool
    let rating: Double
    let college: String
    let isVerified: Bool
}

private struct ChatItem {
    let id: String
    let name: String
    let price: Double
    let image: String
    let status: String
}

private struct Chat: Identifiable {
    let id: String
    let participant: ChatParticipant
    let item: ChatItem
    let lastMessage: String
    let lastTimestamp: String
    let unreadCount: Int
}

private struct ChatMessageUI: Identifiable {
    let id: String
    let senderId: String
    let text: String
    let timestamp: String
    let isRead: Bool
    var offerAmount: Double?
    var offerStatus: String?

    var isMe: Bool { senderId == "me" }
}

// MARK: - Corner radius helper

private struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

// MARK: - Row + bubble

private struct MessagesChatRow: View {
    let chat: Chat
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: chat.participant.avatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(chat.participant.name.prefix(1)).uppercased())
                                .font(Theme.syne(16, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(campusTheme.primary.opacity(0.12), lineWidth: 1))

                    if chat.participant.isOnline {
                        Circle()
                            .fill(campusTheme.primary)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(campusTheme.surface, lineWidth: 2))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(chat.participant.name)
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(chat.lastTimestamp)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(campusTheme.textMuted)
                    }

                    if !chat.item.name.isEmpty, chat.item.name != "Listed item" {
                        Text(chat.item.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(campusTheme.primary.opacity(0.85))
                            .lineLimit(1)
                    }

                    Text(chat.lastMessage.isEmpty ? "Start the conversation" : chat.lastMessage)
                        .font(.system(size: 13, weight: chat.unreadCount > 0 ? .semibold : .regular))
                        .foregroundStyle(chat.unreadCount > 0 ? campusTheme.textPrimary : campusTheme.textMuted)
                        .lineLimit(1)
                }

                if chat.unreadCount > 0 {
                    Text(chat.unreadCount > 9 ? "9+" : "\(chat.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(campusTheme.primary)
                        .clipShape(Capsule())
                }
            }
            .padding(14)
            .background(
                isSelected
                    ? campusTheme.primary.opacity(0.08)
                    : campusTheme.surface.opacity(0.92)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? campusTheme.primary.opacity(0.22) : campusTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
    }
}

private struct MessageBubbleView: View {
    let message: ChatMessageUI
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
            HStack {
                if message.isMe { Spacer(minLength: 60) }
                Text(message.text)
                    .font(.system(size: 14))
                    .foregroundStyle(message.isMe ? Color.white : campusTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(message.isMe ? campusTheme.primary : campusTheme.elevatedSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .cornerRadius(message.isMe ? 4 : 16, corners: message.isMe ? .topRight : .topLeft)
                if !message.isMe { Spacer(minLength: 60) }
            }

            if let offerAmount = message.offerAmount {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CUSTOM OFFER")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(campusTheme.textMuted)
                        Text("$\(offerAmount, specifier: "%.2f")")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(campusTheme.elevatedSurface)

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            // Offer flow — hook when API supports offers
                        } label: {
                            Text("Accept Offer")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(campusTheme.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button {
                            // Decline offer
                        } label: {
                            Text("Decline")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(campusTheme.elevatedSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                }
                .background(campusTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(campusTheme.border, lineWidth: 1)
                )
                .frame(maxWidth: 300, alignment: message.isMe ? .trailing : .leading)
            }

            if message.offerStatus == "accepted" {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                    Text("OFFER ACCEPTED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(campusTheme.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(campusTheme.primary.opacity(0.14))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(campusTheme.primary.opacity(0.28), lineWidth: 1))
            }

            HStack(spacing: 6) {
                Text(message.timestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(campusTheme.textMuted)
                if message.isMe {
                    Image(systemName: message.isRead ? "checkmark.message.fill" : "checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(message.isRead ? campusTheme.primary : campusTheme.textMuted)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: message.isMe ? .trailing : .leading)
        .padding(.bottom, 4)
    }
}

// MARK: - Tab root

struct MessagesView: View {
    @StateObject private var vm = MessagesViewModel()
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var authVM: AuthViewModel
    @Environment(\.campusTheme) private var campusTheme

    @State private var selectedChatId: String?
    @State private var activeTab: String = "buying"
    @State private var searchTerm: String = ""
    @State private var inputValue: String = ""

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isTablet: Bool { sizeClass == .regular }

    private var chats: [Chat] {
        vm.conversations.map { Self.mapConversation($0, meId: authVM.user?.id) }
    }

    private var filteredChats: [Chat] {
        let roleFiltered = chats // Buying/selling split needs product role in API; show all for now.
        guard !searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return roleFiltered
        }
        let q = searchTerm.lowercased()
        return roleFiltered.filter {
            $0.participant.name.lowercased().contains(q) || $0.item.name.lowercased().contains(q)
        }
    }

    private var selectedChat: Chat? { filteredChats.first { $0.id == selectedChatId } }

    private var uiMessages: [ChatMessageUI] {
        let me = authVM.user?.id ?? ""
        return vm.messages.map { Self.mapMessage($0, meId: me) }
    }

    private let quickActions = [
        "Is this still available?",
        "Can you meet today?",
        "What's your best price?",
    ]

    var body: some View {
        ZStack {
            campusTheme.wash.ignoresSafeArea()

            Circle()
                .fill(campusTheme.primary.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 55)
                .offset(x: -140, y: -120)
                .allowsHitTesting(false)

            Circle()
                .fill(campusTheme.secondary.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 160, y: 40)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                if isTablet || selectedChatId == nil {
                    sidebarView
                        .frame(width: isTablet ? 384 : nil)
                        .frame(maxWidth: isTablet ? 384 : .infinity)
                }

                if isTablet || selectedChatId != nil {
                    chatAreaView
                }
            }
        }
        .preferredColorScheme(campusTheme.isDark ? .dark : .light)
        .ignoresSafeArea(edges: .top)
        .task {
            await vm.loadConversations()
        }
        .onChange(of: selectedChatId) { newId in
            guard let newId, !newId.isEmpty else { return }
            Task { await vm.loadMessages(conversationId: newId) }
        }
    }

    // MARK: Sidebar

    private var sidebarView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Inbox")
                    .font(Theme.syne(26, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .padding(.top, 50)

                HStack(spacing: 8) {
                    ForEach(["buying", "selling"], id: \.self) { tab in
                        Button {
                            withAnimation(Motion.snappy) { activeTab = tab }
                            Motion.haptic(.light)
                        } label: {
                            Text(tab == "buying" ? "Buying" : "Selling")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(activeTab == tab ? Color.white : campusTheme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(activeTab == tab ? campusTheme.primary : campusTheme.surface.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(campusTheme.primary.opacity(activeTab == tab ? 0 : 0.16), lineWidth: 1)
                                )
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                    TextField("Search thrift chats…", text: $searchTerm)
                        .font(.system(size: 14))
                        .foregroundStyle(campusTheme.textPrimary)
                        .tint(campusTheme.primary)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(campusTheme.primary.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            campusTheme.primary.opacity(0.14),
                            campusTheme.secondary.opacity(0.08),
                            campusTheme.surface.opacity(0.3),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .ignoresSafeArea(edges: .top)
            }

            if vm.isLoadingConversations && vm.conversations.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredChats.isEmpty {
                emptyInboxView
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredChats) { chat in
                            MessagesChatRow(
                                chat: chat,
                                isSelected: selectedChatId == chat.id,
                                onTap: {
                                    withAnimation(Motion.snappy) { selectedChatId = chat.id }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private var emptyInboxView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text(searchTerm.isEmpty ? "No thrift chats yet" : "No matching chats")
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(searchTerm.isEmpty
                 ? "Message a seller about a find and it’ll show up here."
                 : "Try another name or listing.")
                .font(.system(size: 14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var chatAreaView: some View {
        if let chat = selectedChat {
            activeChatView(chat: chat)
        } else {
            emptyChatView
        }
    }

    private func activeChatView(chat: Chat) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 12) {
                    if !isTablet {
                        Button {
                            withAnimation(Motion.snappy) { selectedChatId = nil }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .frame(width: 36, height: 36)
                                .background(campusTheme.surface.opacity(0.7))
                                .clipShape(Circle())
                                .overlay(Circle().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                    }

                    AsyncImage(url: URL(string: chat.participant.avatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            campusTheme.elevatedSurface
                            Text(String(chat.participant.name.prefix(1)).uppercased())
                                .font(Theme.syne(14, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(chat.participant.name)
                                .font(Theme.syne(15, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                            if chat.participant.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(campusTheme.primary)
                            }
                        }
                        Text(chat.participant.college.isEmpty
                             ? "Campus seller"
                             : chat.participant.college)
                            .font(.system(size: 11))
                            .foregroundStyle(campusTheme.textMuted)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    headerActionButton(icon: "flag")
                    headerActionButton(icon: "ellipsis")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .padding(.top, 44)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [
                            campusTheme.primary.opacity(0.12),
                            campusTheme.surface.opacity(0.35),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }

            HStack(spacing: 12) {
                AsyncImage(url: URL(string: chat.item.image)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    campusTheme.elevatedSurface
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(1)
                    if chat.item.price > 0 {
                        Text("$\(chat.item.price, specifier: "%.0f")")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.primary)
                    }
                }

                Spacer()

                if !chat.item.id.isEmpty {
                    Button {
                        appState.path.append(.productDetail(chat.item.id))
                    } label: {
                        Text("View")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(campusTheme.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.95))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(campusTheme.surface.opacity(0.72))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            Text("Campus safety")
                                .font(Theme.syne(11, weight: .bold))
                                .foregroundStyle(campusTheme.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(campusTheme.primary.opacity(0.12))
                                .clipShape(Capsule())

                            Text("Meet in public campus spots. Don’t share payment info or personal numbers.")
                                .font(.system(size: 12))
                                .foregroundStyle(campusTheme.textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)

                        if vm.isLoadingMessages {
                            ProgressView()
                                .tint(campusTheme.primary)
                                .padding()
                        } else {
                            ForEach(uiMessages) { msg in
                                MessageBubbleView(message: msg)
                                    .id(msg.id)
                            }
                        }

                        Color.clear.frame(height: 20).id("bottom")
                    }
                    .padding(16)
                    .padding(.bottom, 8)
                }
                .onChange(of: uiMessages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickActions, id: \.self) { action in
                        Button {
                            inputValue = action
                            Motion.haptic(.light)
                        } label: {
                            Text(action)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(campusTheme.surface.opacity(0.85))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
                        }
                        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            HStack(spacing: 10) {
                TextField("Type a message…", text: $inputValue, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(campusTheme.textPrimary)
                    .tint(campusTheme.primary)
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                Button {
                    handleSendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? campusTheme.textMuted : Color.white)
                        .frame(width: 40, height: 40)
                        .background(
                            inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? campusTheme.elevatedSurface
                                : campusTheme.primary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
                .disabled(inputValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.trailing, 4)
            }
            .background(campusTheme.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(campusTheme.primary.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 4)
        }
        .background(campusTheme.wash.opacity(0.35))
    }

    private var emptyChatView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(campusTheme.primary.opacity(0.7))
            Text("Pick a chat")
                .font(Theme.syne(20, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text("Select a conversation to keep thrifting.")
                .font(.system(size: 14))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func headerActionButton(icon: String) -> some View {
        Button {
            // Report / more — future
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(campusTheme.textPrimary)
                .frame(width: 36, height: 36)
                .background(campusTheme.surface.opacity(0.7))
                .clipShape(Circle())
                .overlay(Circle().stroke(campusTheme.primary.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.92))
    }

    private func handleSendMessage() {
        let text = inputValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chatId = selectedChatId else { return }
        Task {
            await vm.send(conversationId: chatId, content: text)
            inputValue = ""
        }
    }

    // MARK: - Mappers + time

    private static func mapConversation(_ c: Conversation, meId: String?) -> Chat {
        let me = meId?.lowercased()
        let other = c.participants.first { $0.id.lowercased() != me } ?? c.participants.first
        let u = other
        let name: String = {
            if let s = u?.shopName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
            return u?.username ?? "User"
        }()
        let last = c.messages?.first
        let preview = last?.content ?? ""
        let ts = formatListTimestamp(c.updatedAt ?? last?.createdAt)
        let avatar = u?.avatar ?? ""
        return Chat(
            id: c.id,
            participant: ChatParticipant(
                id: u?.id ?? "",
                name: name,
                avatar: avatar,
                isOnline: false,
                rating: 4.8,
                college: u?.country ?? "",
                isVerified: u?.isVerified == true
            ),
            item: ChatItem(
                id: "",
                name: "Listed item",
                price: 0,
                image: "",
                status: ""
            ),
            lastMessage: preview,
            lastTimestamp: ts,
            unreadCount: 0
        )
    }

    private static func mapMessage(_ m: Message, meId: String) -> ChatMessageUI {
        let me = meId.lowercased()
        let raw = (m.senderId ?? m.sender?.id ?? "").lowercased()
        let sid: String
        if !me.isEmpty, raw == me { sid = "me" }
        else if raw.isEmpty { sid = "them" }
        else { sid = raw }
        return ChatMessageUI(
            id: m.id,
            senderId: sid,
            text: m.content,
            timestamp: formatMessageTime(m.createdAt),
            isRead: m.isRead ?? false,
            offerAmount: nil,
            offerStatus: nil
        )
    }

    private static func parseISO(_ iso: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: iso)
    }

    private static func formatListTimestamp(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty, let parsed = parseISO(iso) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(parsed) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: parsed)
        }
        if cal.isDateInYesterday(parsed) { return "Yesterday" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: parsed)
    }

    private static func formatMessageTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty, let parsed = parseISO(iso) else { return "" }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: parsed)
    }
}
