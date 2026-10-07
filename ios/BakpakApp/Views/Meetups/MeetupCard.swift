import SwiftUI

struct MeetupCard: View {
    let meetup: Meetup
    var showsActions: Bool = true
    var onTap: () -> Void
    var onAccept: (() -> Void)? = nil
    var onDeny: (() -> Void)? = nil

    @EnvironmentObject private var meetupStore: MeetupStore
    @Environment(\.campusTheme) private var campusTheme

    private var meId: String { meetupStore.meId }
    private var peer: MeetupPeer { meetupStore.peer(for: meetup) }
    private var listing: MeetupListingPreview? { meetupStore.listing(for: meetup) }
    private var needsAnswer: Bool { meetup.needsMyResponse(meId: meId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: {
                Motion.haptic(.light)
                onTap()
            }) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            statusPill
                            Text(meetup.spotName)
                                .font(Theme.syne(18, weight: .bold))
                                .foregroundStyle(campusTheme.textPrimary)
                                .multilineTextAlignment(.leading)
                            relativeTime
                        }
                        Spacer(minLength: 8)
                        if let listing {
                            listingThumb(listing)
                        }
                    }

                    HStack(spacing: 10) {
                        AvatarView(urlString: peer.avatarURL, size: 36, initials: peer.firstName)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.name)
                                .font(Theme.syne(14, weight: .semibold))
                                .foregroundStyle(campusTheme.textPrimary)
                            if let listing {
                                Text(listing.title)
                                    .font(Theme.syne(12, weight: .medium))
                                    .foregroundStyle(campusTheme.textMuted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.98))

            if showsActions, needsAnswer {
                HStack(spacing: 10) {
                    Button {
                        Motion.haptic(.medium)
                        onAccept?()
                    } label: {
                        Text("Accept")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(campusTheme.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))

                    Button {
                        Motion.haptic(.light)
                        onDeny?()
                    } label: {
                        Text("Deny")
                            .font(Theme.syne(14, weight: .bold))
                            .foregroundStyle(campusTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(campusTheme.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CampusCardBackground())
    }

    @ViewBuilder
    private var relativeTime: some View {
        if meetup.ticksRelativeTime {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(meetup.relativeTimeLabel(now: context.date))
                    .font(Theme.syne(22, weight: .bold))
                    .foregroundStyle(campusTheme.primary)
            }
        } else {
            Text(meetup.relativeTimeLabel())
                .font(Theme.syne(22, weight: .bold))
                .foregroundStyle(campusTheme.primary)
        }
    }

    private var statusPill: some View {
        let title = meetup.pillTitle(meId: meId, otherFirstName: peer.firstName)
        let live = meetup.status == .confirmed && meetup.isLive
        return Text(title)
            .font(Theme.syne(11, weight: .bold))
            .foregroundStyle(live ? Color.white : campusTheme.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(live ? campusTheme.primary : campusTheme.primary.opacity(0.12))
            .clipShape(Capsule())
    }

    private func listingThumb(_ listing: MeetupListingPreview) -> some View {
        Group {
            if let raw = listing.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty,
               let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        thumbPlaceholder
                    }
                }
            } else {
                thumbPlaceholder
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var thumbPlaceholder: some View {
        ZStack {
            campusTheme.elevatedSurface
            Image(systemName: "tshirt")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(campusTheme.textMuted)
        }
    }
}
