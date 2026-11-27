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
                if product.isSold == true {
                    Text("SOLD")
                        .font(Theme.syne(14, weight: .bold))
                        .foregroundStyle(Color(hex: "#E11D48"))
                } else {
                    Text(MoneyAmount.label(product.price))
                        .font(.subheadline)
                        .foregroundStyle(campusTheme.tint)
                }
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

                    Text(MoneyAmount.label(product.price))
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

/// The one like control on a listing photo: a smoked-glass pill with the like count
/// that flips to white with a red heart once you've liked it.
struct ListingLikePill: View {
    let isLiked: Bool
    let count: Int
    let onLike: () -> Void
    @State private var busy = false
    @State private var pop = false

    static let likeRed = Color(hex: "#E11D48")

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Motion.haptic(isLiked ? .light : .medium)
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { pop = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pop = false }
            }
            onLike()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { busy = false }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isLiked ? Self.likeRed : Color.white)
                    .scaleEffect(pop ? 1.3 : 1)
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.syne(14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isLiked ? Color.black : Color.white)
                        .contentTransition(.numericText())
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, count > 0 ? 14 : 12)
            .frame(minWidth: 40, minHeight: 40)
            .background {
                if isLiked {
                    Capsule().fill(Color.white)
                } else {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Color.black.opacity(0.28))
                    }
                    .environment(\.colorScheme, .dark)
                }
            }
            .overlay(Capsule().stroke(Color.white.opacity(isLiked ? 0 : 0.28), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isLiked)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: count)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "Unlike" : "Like")
        .accessibilityValue(count == 1 ? "1 like" : "\(count) likes")
    }
}

