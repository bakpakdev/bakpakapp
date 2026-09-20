import SwiftUI
import UIKit

/// Crop ratios allowed for listing photos. Width/height is never greater than 1 (no landscape).
enum ListingCropRatio: String, CaseIterable, Identifiable {
    case square
    case portrait45
    case portrait34

    var id: String { rawValue }

    var title: String {
        switch self {
        case .square: return "1:1"
        case .portrait45: return "4:5"
        case .portrait34: return "3:4"
        }
    }

    /// Width ÷ height (always ≤ 1).
    var widthOverHeight: CGFloat {
        switch self {
        case .square: return 1
        case .portrait45: return 4.0 / 5.0
        case .portrait34: return 3.0 / 4.0
        }
    }
}

struct ListingPhotoCropView: View {
    let source: UIImage
    let onCancel: () -> Void
    let onComplete: (UIImage) -> Void

    @Environment(\.campusTheme) private var campusTheme

    @State private var ratio: ListingCropRatio = .square
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotationTurns: Int = 0
    @State private var viewportSize: CGSize = .zero

    private let outputLongEdge: CGFloat = 1200

    private var displayImage: UIImage {
        orientedSource.rotated(byQuarterTurns: rotationTurns)
    }

    private var orientedSource: UIImage {
        source.normalizedOrientation()
    }

    private var baseImageSize: CGSize {
        displayImage.size
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    let crop = cropFrameSize(in: side)

                    ZStack {
                        Color.black

                        Image(uiImage: displayImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: baseDisplaySize(in: crop).width * scale,
                                   height: baseDisplaySize(in: crop).height * scale)
                            .offset(offset)
                            .gesture(dragGesture(crop: crop))
                            .simultaneousGesture(magnifyGesture)

                        // Dim outside crop
                        Rectangle()
                            .fill(Color.black.opacity(0.55))
                            .mask(
                                CropHoleMask(cropSize: crop)
                                    .fill(style: FillStyle(eoFill: true))
                            )
                            .allowsHitTesting(false)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Color.white.opacity(0.95), lineWidth: 1.5)
                            .frame(width: crop.width, height: crop.height)
                            .allowsHitTesting(false)

                        // Rule-of-thirds guides
                        CropGuides()
                            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
                            .frame(width: crop.width, height: crop.height)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .onAppear {
                        viewportSize = geo.size
                        resetFit(for: crop)
                    }
                    .onChange(of: geo.size) { newSize in
                        viewportSize = newSize
                    }
                    .onChange(of: ratio) { _ in
                        let side = min(geo.size.width, geo.size.height)
                        resetFit(for: cropFrameSize(in: side))
                    }
                    .onChange(of: rotationTurns) { _ in
                        let side = min(geo.size.width, geo.size.height)
                        resetFit(for: cropFrameSize(in: side))
                    }
                }
                .frame(maxHeight: .infinity)

                controls
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Adjust photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        let side = min(viewportSize.width, viewportSize.height)
                        let crop = cropFrameSize(in: side)
                        if let out = renderCropped(crop: crop) {
                            onComplete(out)
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(campusTheme.primary == Theme.uoGreen ? Theme.uoYellow : .white)
                }
            }
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Text(dimensionLabel)
                .font(Theme.syne(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 8) {
                ForEach(ListingCropRatio.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { ratio = option }
                    } label: {
                        Text(option.title)
                            .font(Theme.syne(13, weight: .semibold))
                            .foregroundStyle(ratio == option ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(ratio == option ? Color.white : Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 18) {
                Button {
                    rotationTurns -= 1
                } label: {
                    Label("Rotate", systemImage: "rotate.left")
                        .font(Theme.syne(14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Button {
                    let side = min(viewportSize.width, viewportSize.height)
                    resetFit(for: cropFrameSize(in: side))
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(Theme.syne(14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Spacer()

                Text("Pinch · drag")
                    .font(Theme.syne(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background(Color(white: 0.08))
    }

    private var dimensionLabel: String {
        let out = outputPixelSize
        return "\(Int(out.width)) × \(Int(out.height)) · \(ratio.title) max"
    }

    private var outputPixelSize: CGSize {
        let aspect = ratio.widthOverHeight
        if aspect >= 1 {
            return CGSize(width: outputLongEdge, height: outputLongEdge / aspect)
        }
        return CGSize(width: outputLongEdge * aspect, height: outputLongEdge)
    }

    private func cropFrameSize(in side: CGFloat) -> CGSize {
        let maxSide = max(side - 24, 120)
        let aspect = ratio.widthOverHeight
        if aspect >= 1 {
            let w = maxSide
            return CGSize(width: w, height: w / aspect)
        }
        let h = maxSide
        return CGSize(width: h * aspect, height: h)
    }

    /// Size of the image when scale == 1, covering the crop frame (like scaledToFill).
    private func baseDisplaySize(in crop: CGSize) -> CGSize {
        let img = baseImageSize
        guard img.width > 0, img.height > 0 else { return crop }
        let cover = max(crop.width / img.width, crop.height / img.height)
        return CGSize(width: img.width * cover, height: img.height * cover)
    }

    private func resetFit(for crop: CGSize) {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        _ = crop
    }

    private func dragGesture(crop: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                offset = clampedOffset(crop: crop)
                lastOffset = offset
            }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = max(1, min(lastScale * value, 6))
            }
            .onEnded { _ in
                scale = max(1, min(scale, 6))
                lastScale = scale
                let side = min(viewportSize.width, viewportSize.height)
                offset = clampedOffset(crop: cropFrameSize(in: side))
                lastOffset = offset
            }
    }

    private func clampedOffset(crop: CGSize) -> CGSize {
        let display = baseDisplaySize(in: crop)
        let w = display.width * scale
        let h = display.height * scale
        let maxX = max(0, (w - crop.width) / 2)
        let maxY = max(0, (h - crop.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func renderCropped(crop: CGSize) -> UIImage? {
        let rotated = displayImage
        let rotSize = rotated.size
        guard rotSize.width > 0, rotSize.height > 0 else { return nil }

        let outSize = outputPixelSize
        let display = baseDisplaySize(in: crop)
        let drawW = display.width * scale
        let drawH = display.height * scale

        let imageOriginInCropSpace = CGPoint(
            x: (crop.width - drawW) / 2 + offset.width,
            y: (crop.height - drawH) / 2 + offset.height
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: outSize, format: format)

        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: outSize))

            let px = outSize.width / crop.width
            let drawRect = CGRect(
                x: imageOriginInCropSpace.x * px,
                y: imageOriginInCropSpace.y * px,
                width: drawW * px,
                height: drawH * px
            )
            rotated.draw(in: drawRect)
        }
    }
}

// MARK: - Masks / guides

private struct CropHoleMask: Shape {
    let cropSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let crop = CGRect(
            x: (rect.width - cropSize.width) / 2,
            y: (rect.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )
        path.addRect(crop)
        return path
    }
}

private struct CropGuides: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            let y = rect.minY + rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

// MARK: - UIImage helpers

private extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func rotated(byQuarterTurns turns: Int) -> UIImage {
        let t = ((turns % 4) + 4) % 4
        if t == 0 { return self }
        let radians = CGFloat(t) * .pi / 2
        var newSize = size
        if t % 2 != 0 {
            newSize = CGSize(width: size.height, height: size.width)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            c.rotate(by: radians)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}
