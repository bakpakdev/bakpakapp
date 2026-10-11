import Foundation
import SwiftUI
import Supabase

@MainActor
final class ProductListViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = ProductService()
    private var loadGeneration = 0

    func beginFreshHomeLoad() {
        loadGeneration += 1
        products = []
        isLoading = true
        errorMessage = nil
    }

    func loadDiscover(school: String? = nil) async {
        let gen = loadGeneration
        isLoading = true
        defer {
            if gen == loadGeneration { isLoading = false }
        }
        do {
            let fetched = try await service.discover(school: school)
            guard gen == loadGeneration else { return }
            products = fetched
        } catch {
            guard gen == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    func search(query: String, category: String? = nil, school: String? = nil) async {
        let gen = loadGeneration
        isLoading = true
        defer {
            if gen == loadGeneration { isLoading = false }
        }
        do {
            let fetched = try await service.search(query: query, category: category, school: school)
            guard gen == loadGeneration else { return }
            products = fetched
        } catch {
            guard gen == loadGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var isLoadingConversations = false
    @Published var isLoadingMessages = false
    @Published var errorMessage: String?
    @Published var isSending = false

    private let service = MessageService()
    private var liveTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var activeConversationId: String?
    /// Conversation currently shown in the thread (used to clear when switching).
    private var displayedConversationId: String?

    func loadConversations() async {
        isLoadingConversations = true
        defer { isLoadingConversations = false }
        do {
            conversations = try await service.conversations()
        } catch {
            errorMessage = error.localizedDescription
            conversations = []
        }
    }

    func resetForAccountChange() {
        stopLiveUpdates()
        conversations = []
        messages = []
        errorMessage = nil
        isSending = false
        activeConversationId = nil
        displayedConversationId = nil
    }

    func markRead(conversationId: String) async {
        guard !conversationId.isEmpty else { return }
        InboxReadStore.markRead(conversationId)
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].unreadCount = 0
        }
        try? await service.markRead(conversationId: conversationId)
    }

    func loadMessages(conversationId: String) async {
        isLoadingMessages = true
        defer { isLoadingMessages = false }
        // Drop the previous thread so the UI doesn't flash old messages / skip scroll.
        if displayedConversationId != conversationId {
            messages = []
            displayedConversationId = conversationId
        }
        do {
            let fetched = try await service.messages(conversationId: conversationId)
            mergeMessages(fetched)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Call after clearing the text field. Appends a bubble immediately, then syncs to Supabase.
    func send(conversationId: String, content: String, senderId: String?) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !conversationId.isEmpty else { return }

        let tempId = "local-\(UUID().uuidString)"
        let now = ISO8601DateFormatter().string(from: Date())
        let optimistic = Message(
            id: tempId,
            content: trimmed,
            senderId: senderId,
            conversationId: conversationId,
            isRead: true,
            createdAt: now,
            sender: nil
        )
        messages.append(optimistic)
        isSending = true
        errorMessage = nil

        do {
            let sent = try await service.send(conversationId: conversationId, content: trimmed)
            if let idx = messages.firstIndex(where: { $0.id == tempId }) {
                messages[idx] = sent
            } else {
                upsertMessage(sent)
            }
        } catch {
            messages.removeAll { $0.id == tempId }
            errorMessage = error.localizedDescription
        }
        isSending = false
    }

    func startLiveUpdates(conversationId: String) {
        guard !conversationId.isEmpty else { return }
        if activeConversationId == conversationId, liveTask != nil || pollTask != nil { return }
        stopLiveUpdates()
        activeConversationId = conversationId

        liveTask = Task { [weak self] in
            await self?.subscribeRealtime(conversationId: conversationId)
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.refreshMessagesQuietly(conversationId: conversationId)
            }
        }
    }

    func stopLiveUpdates() {
        liveTask?.cancel()
        pollTask?.cancel()
        liveTask = nil
        pollTask = nil
        activeConversationId = nil
        let channel = realtimeChannel
        realtimeChannel = nil
        if let channel {
            Task {
                if let client = await SupabaseManager.shared.clientWithValidSession() {
                    await client.removeChannel(channel)
                }
            }
        }
    }

    private func refreshMessagesQuietly(conversationId: String) async {
        do {
            let fetched = try await service.messages(conversationId: conversationId)
            mergeMessages(fetched)
        } catch {}
    }

    private func subscribeRealtime(conversationId: String) async {
        guard let client = await SupabaseManager.shared.clientWithValidSession() else { return }
        let channel = client.channel("messages:\(conversationId)")
        realtimeChannel = channel

        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: "conversation_id=eq.\(conversationId)"
        )

        do {
            try await channel.subscribeWithError()
        } catch {
            return
        }

        for await insertion in insertions {
            guard !Task.isCancelled else { break }
            do {
                struct Row: Decodable {
                    let id: String
                    let content: String
                    let created_at: String?
                    let sender_id: String?
                    let is_read: Bool?
                    let conversation_id: String?
                }
                let row = try insertion.decodeRecord(as: Row.self, decoder: JSONDecoder())
                let message = Message(
                    id: row.id,
                    content: row.content,
                    senderId: row.sender_id,
                    conversationId: row.conversation_id ?? conversationId,
                    isRead: row.is_read,
                    createdAt: row.created_at,
                    sender: nil
                )
                upsertMessage(message)
            } catch {
                continue
            }
        }
    }

    private func mergeMessages(_ fetched: [Message]) {
        let locals = messages.filter { local in
            local.id.hasPrefix("local-")
                && !fetched.contains {
                    $0.content == local.content
                        && ($0.senderId ?? "").lowercased() == (local.senderId ?? "").lowercased()
                }
        }
        messages = (fetched + locals).sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }

    private func upsertMessage(_ message: Message) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
            return
        }
        if let idx = messages.firstIndex(where: {
            $0.id.hasPrefix("local-")
                && $0.content == message.content
                && ($0.senderId ?? "").lowercased() == (message.senderId ?? "").lowercased()
        }) {
            messages[idx] = message
            return
        }
        messages.append(message)
        messages.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }
}
