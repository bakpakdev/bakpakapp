import SwiftUI

/// Legacy route target. All chats open in the Inbox thread (`MessagesView`).
struct ConversationView: View {
    let conversationId: String
    let otherUserId: String?
    var productId: String? = nil

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Color.clear
            .task {
                appState.openInboxChat(
                    conversationId: conversationId,
                    otherUserId: otherUserId,
                    productId: productId
                )
            }
    }
}
