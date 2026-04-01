import SwiftUI

struct ConversationView: View {
    let conversationId: String
    let otherUserId: String?

    @StateObject private var vm = MessagesViewModel()
    @State private var input = ""
    private let service = MessageService()

    var body: some View {
        VStack {
            List(vm.messages) { message in
                VStack(alignment: .leading) {
                    Text(message.sender?.username ?? "User").font(.caption).foregroundStyle(.secondary)
                    Text(message.content)
                }
            }

            HStack {
                TextField("Message", text: $input).textFieldStyle(.roundedBorder)
                Button("Send") {
                    Task {
                        let id = await ensureConversationId()
                        await vm.send(conversationId: id, content: input)
                        input = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.uoGreen)
            }
            .padding()
        }
        .navigationTitle("Conversation")
        .task {
            let id = await ensureConversationId()
            await vm.loadMessages(conversationId: id)
        }
    }

    private func ensureConversationId() async -> String {
        if !conversationId.isEmpty { return conversationId }
        guard let otherUserId else { return "" }
        do {
            let convo = try await service.openOrCreate(otherUserId: otherUserId)
            return convo.id
        } catch {
            return ""
        }
    }
}
