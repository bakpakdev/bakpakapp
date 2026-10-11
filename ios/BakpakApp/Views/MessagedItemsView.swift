import SwiftUI

struct MessagedItemsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.campusTheme) private var campusTheme

    @State private var items: [MessagedListing] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let service = MessageService()

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView()
                    .tint(campusTheme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, items.isEmpty {
                emptyState(
                    title: "Couldn't load items",
                    systemImage: "exclamationmark.bubble",
                    detail: errorMessage
                )
            } else if items.isEmpty {
                emptyState(
                    title: "No messaged items yet",
                    systemImage: "bubble.left.and.bubble.right",
                    detail: "When you message a seller about a listing, it shows up here."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
                            messagedRow(item)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .navigationTitle("Messaged")
        .navigationBarTitleDisplayMode(.inline)
        .campusScreenStyle()
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func messagedRow(_ item: MessagedListing) -> some View {
        Button {
            Motion.haptic(.light)
            appState.path.append(
                .conversation(item.conversationId, item.otherUserId, item.id)
            )
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: URL(string: item.imageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        campusTheme.elevatedSurface
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .grayscale(item.isSold ? 1 : 0)
                .opacity(item.isSold ? 0.72 : 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Theme.syne(15, weight: .semibold))
                        .foregroundStyle(campusTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(item.sellerName)
                        .font(Theme.syne(13, weight: .medium))
                        .foregroundStyle(campusTheme.textMuted)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("$\(Int(item.price))")
                            .font(Theme.syne(15, weight: .bold))
                            .foregroundStyle(campusTheme.primary)

                        if item.isSold {
                            Text("SOLD")
                                .font(Theme.syne(11, weight: .bold))
                                .foregroundStyle(campusTheme.textMuted)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(campusTheme.textMuted)
            }
            .padding(12)
            .background(campusTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(campusTheme.border.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))
        .contextMenu {
            Button {
                appState.path.append(.productDetail(item.id))
            } label: {
                Label("View listing", systemImage: "tag")
            }
        }
    }

    private func emptyState(title: String, systemImage: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(campusTheme.primary.opacity(0.85))
            Text(title)
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(detail)
                .font(Theme.syne(14, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            await BlockStore.shared.refreshIfNeeded()
            let fetched = try await service.messagedListings()
            items = fetched.filter { !BlockStore.shared.isHidden($0.otherUserId) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
