import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var user: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var baseURL = "http://localhost:5000/api"

    private let authService = AuthService()

    init() {
        if KeychainManager.shared.readToken() != nil {
            isAuthenticated = true
            Task { await refreshMe() }
        }
    }

    func applyServerURL() {
        APIClient.shared.setBaseURL(baseURL)
    }

    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            applyServerURL()
            let response = try await authService.login(email: email, password: password)
            KeychainManager.shared.saveToken(response.token)
            user = response.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func register(email: String, username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            applyServerURL()
            let response = try await authService.register(email: email, username: username, password: password)
            KeychainManager.shared.saveToken(response.token)
            user = response.user
            isAuthenticated = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refreshMe() async {
        do {
            user = try await authService.me()
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            user = nil
        }
    }

    func logout() {
        KeychainManager.shared.clearToken()
        isAuthenticated = false
        user = nil
    }
}

@MainActor
final class ProductListViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = ProductService()

    func loadDiscover() async {
        isLoading = true
        do {
            products = try await service.discover()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func search(query: String, category: String? = nil) async {
        isLoading = true
        do {
            products = try await service.search(query: query, category: category)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

@MainActor
final class MessagesViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var messages: [Message] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = MessageService()

    func loadConversations() async {
        isLoading = true
        do {
            conversations = try await service.conversations()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMessages(conversationId: String) async {
        isLoading = true
        do {
            messages = try await service.messages(conversationId: conversationId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func send(conversationId: String, content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let sent = try await service.send(conversationId: conversationId, content: content)
            messages.append(sent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
