import SwiftUI

struct ConversationView: View {
    let conversationId: String
    let otherUserId: String?
    var productId: String? = nil

    var body: some View {
        InboxThreadView(
            conversationId: conversationId,
            otherUserId: otherUserId,
            productId: productId
        )
    }
}
