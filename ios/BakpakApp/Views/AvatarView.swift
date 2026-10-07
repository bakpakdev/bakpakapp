import SwiftUI

/// Loads a profile photo, skipping empty/invalid URLs so AsyncImage doesn’t hang.
struct AvatarView: View {
    let urlString: String?
    var size: CGFloat = 48
    var cornerRadius: CGFloat? = nil
    var initials: String = "?"
    @Environment(\.campusTheme) private var campusTheme

    private var url: URL? {
        let raw = (urlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw), url.scheme != nil else { return nil }
        return url
    }

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            campusTheme.elevatedSurface
            Text(String(initials.prefix(1)).uppercased())
                .font(Theme.syne(max(12, size * 0.34), weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
        }
    }
}
