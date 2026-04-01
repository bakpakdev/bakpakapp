import SwiftUI

struct ProductCardView: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: product.images?.first?.url ?? "")) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.15)
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(product.title).font(.headline).lineLimit(1)
                Text("$\(Int(product.price))").font(.subheadline).foregroundStyle(Theme.uoGreen)
                Text(product.category ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}
