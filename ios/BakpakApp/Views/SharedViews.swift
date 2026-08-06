import SwiftUI

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
