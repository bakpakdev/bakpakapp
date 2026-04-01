import SwiftUI

struct MessagesView: View {
    @StateObject private var vm = MessagesViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var segment = 0

    var body: some View {
        VStack {
            Picker("Mode", selection: $segment) {
                Text("Buying").tag(0)
                Text("Selling").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            List(vm.conversations) { convo in
                let other = convo.participants.first
                HStack {
                    Text(other?.username ?? "Conversation")
                    Spacer()
                    Text(convo.messages?.first?.content ?? "")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.path.append(.conversation(convo.id, nil))
                }
            }
        }
        .task { await vm.loadConversations() }
        .navigationTitle("Messages")
        .tint(Theme.uoGreen)
    }
}
