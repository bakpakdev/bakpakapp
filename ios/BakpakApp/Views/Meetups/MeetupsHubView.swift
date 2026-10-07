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
                            message: "Open a chat and tap Meetup to propose a campus spot and time. Invites you send or get will land here."
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
                        onDeny: { Task { await respond(meetup, accept: false) } }
                    )
                }
            }
        }
    }

    private func respond(_ meetup: Meetup, accept: Bool) async {
        do {
            let updated = try await MeetupService.respond(id: meetup.id, accept: accept)
            meetupStore.apply(updated)
            await MeetupChatActions.send(accept ? .accepted : .declined, meetup: meetup, spots: campusTheme.meetupLocations)
            Motion.haptic(.medium)
        } catch {}
    }
}
