import SwiftUI

struct ConversationView: View {
    let conversationId: String
    let otherUserId: String?
    var productId: String? = nil
    @Environment(\.campusTheme) private var campusTheme

    @StateObject private var vm = MessagesViewModel()
    @State private var input = ""
    @State private var resolvedId: String = ""
    private let service = MessageService()

    var body: some View {
        VStack {
            List(vm.messages) { message in
                VStack(alignment: .leading) {
                    Text(message.sender?.username ?? "User")
                        .font(Theme.syne(11, weight: .semibold))
                        .foregroundStyle(campusTheme.primary)
                    Text(message.content)
                }
            }
            .scrollContentBackground(.hidden)

            HStack {
                TextField("Message", text: $input)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(campusTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(campusTheme.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("Send") {
                    Task {
                        let id = await ensureConversationId()
                        await vm.send(conversationId: id, content: input)
                        input = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(campusTheme.primary)
            }
            .padding()
        }
        .navigationTitle("Conversation")
        .campusScreenStyle()
        .task {
            let id = await ensureConversationId()
            await vm.loadMessages(conversationId: id)
        }
    }

    private func ensureConversationId() async -> String {
        if !resolvedId.isEmpty { return resolvedId }
        if !conversationId.isEmpty {
            resolvedId = conversationId
            return resolvedId
        }
        guard let otherUserId else { return "" }
        do {
            let convo = try await service.openOrCreate(otherUserId: otherUserId, productId: productId)
            resolvedId = convo.id
            return resolvedId
        } catch {
            return ""
        }
    }
}
