import SwiftUI

struct MeetupsHubView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme

    private var isEmpty: Bool {
        meetupStore.needsResponse.isEmpty
            && meetupStore.today.isEmpty
            && meetupStore.upcoming.isEmpty
            && meetupStore.past.isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            CampusPageBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    CampusPageHeader(title: "meetups", subtitle: "campus pickups")

                    if isEmpty {
                        CampusEmptyCard(
                            systemImage: "mappin.and.ellipse",
                            title: "No meetups yet",
                            message: "Request a meetup from a listing, or propose one in chat. Invites you send or get will land here."
                        )
                    } else {
                        section(title: "needs your answer", meetups: meetupStore.needsResponse)
                        section(title: "today", meetups: meetupStore.today)
                        section(title: "upcoming", meetups: meetupStore.upcoming)
                        section(title: "past", meetups: meetupStore.past, showsActions: false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .refreshable {
                await meetupStore.refresh()
            }
        }
        .campusPageStyle()
    }

    @ViewBuilder
    private func section(title: String, meetups: [Meetup], showsActions: Bool = true) -> some View {
        if !meetups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(Theme.syne(18, weight: .semibold))
                    .foregroundStyle(campusTheme.textPrimary)

                ForEach(meetups) { meetup in
                    MeetupCard(
                        meetup: meetup,
                        showsActions: showsActions,
                        onTap: {
                            appState.path.append(.meetupDetail(meetup.id))
                        },
                        onAccept: { Task { await respond(meetup, accept: true) } },
                        onDeny: { Task { await respond(meetup, accept: false) } },
                        onPayOrReceive: showsActions
                            ? { appState.path.append(.meetupPay(meetup.id)) }
                            : nil
                    )
                }
            }
        }
    }

    private func respond(_ meetup: Meetup, accept: Bool) async {
        do {
            let hadChat = MeetupService.shouldPostChatStatus(for: meetup)
            let updated = try await MeetupService.respond(id: meetup.id, accept: accept)
            meetupStore.apply(updated)
            if hadChat {
                await MeetupChatActions.send(
                    accept ? .accepted : .declined,
                    meetup: updated,
                    spots: campusTheme.meetupLocations
                )
            } else if accept, !updated.conversationId.isEmpty {
                appState.openInboxChat(
                    conversationId: updated.conversationId,
                    otherUserId: updated.otherUserId(meId: meetupStore.meId),
                    productId: updated.productId
                )
            }
            Motion.haptic(.medium)
        } catch {}
    }
}
