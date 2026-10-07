import SwiftUI

/// Single continuous bubble path with a small bottom-corner tip (strokes cleanly).
struct ChatBubbleShape: Shape {
    var isFromMe: Bool
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let tipH: CGFloat = 5.5
        let tipW: CGFloat = 7.5
        let bodyBottom = h - tipH
        let r = min(cornerRadius, min(w, bodyBottom) / 2)

        var path = Path()

        if isFromMe {
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(
                center: CGPoint(x: w - r, y: r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            // Right edge all the way to the bottom corner (no skipped gap).
            path.addLine(to: CGPoint(x: w, y: bodyBottom))
            // Tip point, then rejoin bottom — straight segments stay solid.
            path.addLine(to: CGPoint(x: w - 0.8, y: h))
            path.addLine(to: CGPoint(x: w - tipW, y: bodyBottom))
            path.addLine(to: CGPoint(x: r, y: bodyBottom))
            path.addArc(
                center: CGPoint(x: r, y: bodyBottom - r),
                radius: r,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(
                center: CGPoint(x: r, y: r),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: r, y: 0))
            path.addLine(to: CGPoint(x: w - r, y: 0))
            path.addArc(
                center: CGPoint(x: w - r, y: r),
                radius: r,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: w, y: bodyBottom - r))
            path.addArc(
                center: CGPoint(x: w - r, y: bodyBottom - r),
                radius: r,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: tipW, y: bodyBottom))
            path.addLine(to: CGPoint(x: 0.8, y: h))
            path.addLine(to: CGPoint(x: 0, y: bodyBottom))
            path.addLine(to: CGPoint(x: 0, y: r))
            path.addArc(
                center: CGPoint(x: r, y: r),
                radius: r,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.closeSubpath()
        }

        return path
    }
}

struct ChatBubbleTail: View {
    let isFromMe: Bool
    let fill: Color
    let stroke: Color?

    var body: some View {
        ChatBubbleShape(isFromMe: isFromMe)
            .fill(fill)
            .overlay {
                if let stroke {
                    ChatBubbleShape(isFromMe: isFromMe)
                        .stroke(stroke, lineWidth: 1)
                }
            }
    }
}

struct ProductCardView: View {
    let product: Product
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: product.images?.first?.url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                campusTheme.elevatedSurface
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title)
                    .font(Theme.syne(15, weight: .bold))
                    .foregroundStyle(campusTheme.textPrimary)
                    .lineLimit(1)
                Text("$\(Int(product.price))")
                    .font(.subheadline)
                    .foregroundStyle(campusTheme.primary)
                Text(product.category ?? "")
                    .font(.caption)
                    .foregroundStyle(campusTheme.textMuted)
            }
            Spacer()
        }
    }
}

/// Shared shop/profile grid cell (active listings + greyscale SOLD).
struct ShopProductCell: View {
    let product: Product
    let itemSize: CGFloat
    let onTap: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    private var primaryImage: ProductImage? {
        product.images?.first(where: { $0.isPrimary == true }) ?? product.images?.first
    }

    private var isSold: Bool { product.isSold == true }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                AsyncImage(url: URL(string: primaryImage?.url ?? "")) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    campusTheme.elevatedSurface
                }
                .frame(width: itemSize, height: itemSize * 1.33)
                .clipped()
                .grayscale(isSold ? 1 : 0)
                .opacity(isSold ? 0.55 : 1)

                if isSold {
                    Color.black.opacity(0.28)
                    Text("SOLD")
                        .font(Theme.syne(18, weight: .bold))
                        .foregroundStyle(.white)
                        .tracking(1.4)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                } else {
                    VStack {
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.55)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        .frame(height: 52)
                    }

                    Text("$\(Int(product.price))")
                        .font(Theme.syne(13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: itemSize, height: itemSize * 1.33)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(campusTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
    }
}

/// Heart + save controls overlaid on listing thumbnails / detail heroes.
struct ListingReactionButtons: View {
    let isLiked: Bool
    let isSaved: Bool
    var compact: Bool = true
    let onLike: () -> Void
    let onSave: () -> Void
    @State private var busy = false

    private var buttonSize: CGFloat { compact ? 32 : 40 }
    private var iconSize: CGFloat { compact ? 14 : 16 }

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            reactionButton(
                systemName: isLiked ? "heart.fill" : "heart",
                tint: isLiked ? Color(hex: "#E11D48") : .white,
                accessibility: isLiked ? "Unlike" : "Like",
                action: onLike
            )
            reactionButton(
                systemName: isSaved ? "bookmark.fill" : "bookmark",
                tint: isSaved ? Color(hex: "#F59E0B") : .white,
                accessibility: isSaved ? "Unsave" : "Save",
                action: onSave
            )
        }
    }

    private func reactionButton(
        systemName: String,
        tint: Color,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !busy else { return }
            busy = true
            Motion.haptic(.light)
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { busy = false }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: buttonSize, height: buttonSize)
                .background(Color.black.opacity(0.42))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}
