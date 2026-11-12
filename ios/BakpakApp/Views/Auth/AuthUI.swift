import SwiftUI

// MARK: - Auth background

/// Background for the signed-out screens. `liquid` shows the animated satin; otherwise the
/// original soft glows. Both layers stay mounted so switching between them crossfades.
struct AuthPageBackground: View {
    var liquid: Bool = true
    var intensity: Double = 0.75

    var body: some View {
        ZStack(alignment: .top) {
            PopupBrand.background.ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.07))
                .frame(width: 300, height: 300)
                .blur(radius: 55)
                .offset(x: -150, y: -110)

            Circle()
                .fill(Color.white.opacity(0.045))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: 175, y: 20)

            LiquidSatinBackground(intensity: intensity)
                .opacity(liquid ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.6), value: liquid)
        .allowsHitTesting(false)
    }
}

// MARK: - Liquid satin

/// Dark liquid silk that slowly ripples and catches light. Rendered as a tiny grayscale
/// image on the CPU and scaled up, so it runs on iOS 16 with no shaders. The phase comes
/// from the wall clock, so every auth screen shows the same frame and crossfades are seamless.
struct LiquidSatinBackground: View {
    /// 1 = welcome screen strength; lower keeps forms easier to read.
    var intensity: Double = 1

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || scenePhase != .active)) { context in
            let t = reduceMotion ? 4.0 : context.date.timeIntervalSinceReferenceDate * 0.35
            if let image = SatinRenderer.image(time: t, intensity: intensity) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .blur(radius: 4)
                    .scaleEffect(1.04)
            } else {
                PopupBrand.background
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private enum SatinRenderer {
    static let width = 72
    static let height = 156
    private static let colorSpace = CGColorSpaceCreateDeviceGray()

    static func image(time t: Double, intensity: Double) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let w = Double(width), h = Double(height)
        for y in 0..<height {
            let ny = Double(y) / h
            let fade = 1 - min(1, abs(ny - 0.42) * 1.25)
            let lift = 0.35 + 0.65 * fade
            let rowA = sin(ny * 4 + t) * 1.5
            for x in 0..<width {
                let nx = Double(x) / w
                var v = sin(nx * 6 + t * 1.1 + rowA)
                v += sin(ny * 5 - t * 0.8 + cos(nx * 3 - t * 0.6) * 2)
                v += sin((nx + ny) * 4 + t * 0.5)
                v /= 3
                let band = pow(max(0, sin(v * 3.2)), 6)
                let l = 10 + (22 * (v * 0.5 + 0.5) + 95 * band) * lift * intensity
                pixels[y * width + x] = UInt8(max(0, min(255, l)))
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

// MARK: - Glass buttons (welcome screen)

/// Glossy white pill: the main call to action.
struct GlossyPillBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(
                colors: [Color.white, Color(hex: "#E1E1E1")],
                startPoint: .top, endPoint: .bottom
            ))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white, Color.white.opacity(0.0)], startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
            )
            .overlay(
                shape.fill(LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.08)],
                    startPoint: .center, endPoint: .bottom
                ))
            )
            .shadow(color: Color.white.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

/// Frosted dark glass: secondary actions over the satin.
struct FrostedGlassBackground: View {
    var cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                shape.fill(LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                    startPoint: .top, endPoint: .bottom
                ))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.26), Color.white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 14, x: 0, y: 10)
    }
}

// MARK: - Shared auth field / button

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PopupBrand.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PopupBrand.border, lineWidth: 1)
            )
            .foregroundStyle(PopupBrand.textPrimary)
            .tint(PopupBrand.textPrimary)
    }
}

extension View {
    func authFieldStyle() -> some View {
        modifier(AuthFieldStyle())
    }
}

struct AuthPrimaryButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: {
            Motion.haptic(.medium)
            action()
        }) {
            HStack {
                label
                    .font(Theme.syne(16, weight: .semibold))
            }
            .foregroundStyle(PopupBrand.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(PopupBrand.button)
            )
        }
        .buttonStyle(BouncyButtonStyle(pressedScale: 0.96))
    }
}

struct AuthScreenChrome<Content: View>: View {
    var liquidBackground: Bool = true
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            AuthPageBackground(liquid: liquidBackground)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        Motion.haptic(.light)
                        onBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(PopupBrand.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(PopupBrand.field)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(PopupBrand.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(BouncyButtonStyle(pressedScale: 0.94))

                    PopupWordmark(scale: .header, alignment: .leading)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                content
            }
        }
    }
}
