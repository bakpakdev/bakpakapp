import SwiftUI

// MARK: - "Sheet lift" launch animation
//
// 1. "pop" / "up" letters slide up out of an invisible line, one after another.
// 2. A silver shine sweeps across the wordmark.
// 3. The black sheet swipes up with an arched bottom edge (silver rim), carrying
//    the logo off the top while Home slides up from underneath.
//
// Everything is a pure function of elapsed time `t` (driven by a TimelineView),
// ported 1:1 from the approved web preview (launch-animation-ideas, idea 3).

enum SheetLift {
    // Wordmark geometry (points)
    static let fontSize: CGFloat = 88
    static var wordHeight: CGFloat { fontSize * 1.12 }
    static let wordGap: CGFloat = -8
    static let popDrop: CGFloat = 22
    static var tracking: CGFloat { -0.02 * fontSize }

    // Timeline (seconds)
    static let letterStart: Double = 0.10
    static let letterStagger: Double = 0.11
    static let letterDuration: Double = 0.50
    static let shineStart: Double = 1.05
    static let shineDuration: Double = 0.55
    /// Home is mounted (hidden under the opaque sheet) a moment before the lift.
    static let mountHome: Double = 1.60
    static let liftStart: Double = 1.80
    static let liftDuration: Double = 0.85
    static var end: Double { liftStart + liftDuration }

    // Reduce Motion: fade the static wordmark in, hold, then cross-fade to Home.
    static let rmFadeIn: Double = 0.25
    static let rmFadeOutStart: Double = 0.65
    static let rmFadeOut: Double = 0.28
    static var rmEnd: Double { rmFadeOutStart + rmFadeOut }
    static var rmMountHome: Double { rmFadeOutStart - 0.05 }

    /// Arch height of the sheet's bottom edge, on a 393pt-wide screen.
    static let archHeight: CGFloat = 173.3
    /// Home starts this fraction of the screen height lower and rises into place.
    static let homeParallax: CGFloat = 0.18
    static let homeDim: Double = 0.45

    static let letterCurve = CubicBezier(0.2, 0.9, 0.3, 1)
    static let liftCurve = CubicBezier(0.65, 0, 0.2, 1)
    static let easeOut = CubicBezier(0, 0, 0.58, 1)

    /// 0 → 1 progress of the sheet lift.
    static func liftProgress(_ t: Double) -> Double {
        liftCurve(segment(t, liftStart, liftDuration))
    }

    static func segment(_ t: Double, _ start: Double, _ duration: Double) -> Double {
        min(1, max(0, (t - start) / duration))
    }
}

/// CSS-style cubic-bezier timing curve evaluated at an arbitrary time.
struct CubicBezier {
    let x1, y1, x2, y2: Double
    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, u = 0.5
        for _ in 0..<40 {
            u = (lo + hi) / 2
            let x = 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u
            if x < t { lo = u } else { hi = u }
        }
        return 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat {
    a + (b - a) * CGFloat(p)
}

// MARK: - Launch reveal container

/// Plays the splash over `content`, then lifts it away to reveal `content`.
/// `content` keeps the same identity before and after the splash finishes.
struct LaunchReveal<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var done = false
    @State private var didStart = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: done)) { context in
            let t = done ? .infinity : context.date.timeIntervalSince(start)
            let p = (done || reduceMotion) ? 1 : SheetLift.liftProgress(t)
            let mountAt = reduceMotion ? SheetLift.rmMountHome : SheetLift.mountHome
            let screenHeight = UIScreen.main.bounds.height

            ZStack {
                if done || t >= mountAt {
                    content()
                        .offset(y: (1 - CGFloat(p)) * screenHeight * SheetLift.homeParallax)
                        .overlay {
                            Color.black
                                .opacity(SheetLift.homeDim * (1 - p))
                                .ignoresSafeArea()
                                .allowsHitTesting(false)
                        }
                }

                if !done {
                    SplashScreen(t: t)
                        .ignoresSafeArea()
                        .zIndex(1)
                }
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            start = Date()
            let total = reduceMotion ? SheetLift.rmEnd : SheetLift.end
            DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.03) {
                done = true
            }
        }
    }
}

// MARK: - Splash (one frame at time t)

struct SplashScreen: View {
    let t: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let markFont = Theme.syne(SheetLift.fontSize, weight: .heavy)

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                reducedMotion(size: geo.size)
            } else {
                animated(size: geo.size)
            }
        }
    }

    // MARK: Animated

    private func animated(size: CGSize) -> some View {
        let w = size.width, h = size.height
        let p = SheetLift.liftProgress(t)
        let arch = SheetLift.archHeight * w / 393
        let restEdge = h + arch + 13
        // Bottom edge of the sheet at the screen sides; the middle is `arch` higher.
        let edgeY = lerp(restEdge, -40, p)
        // Logo rides up with the sheet.
        let dy = min(0, edgeY - restEdge) * 0.9

        let qs = (0..<4).map { i in
            SheetLift.letterCurve(SheetLift.segment(
                t, SheetLift.letterStart + Double(i) * SheetLift.letterStagger, SheetLift.letterDuration))
        }
        let shine = SheetLift.segment(t, SheetLift.shineStart, SheetLift.shineDuration)

        return ZStack {
            ZStack {
                Color.black
                wordmark(size: size, qs: qs, dy: dy, masked: true)
                if shine > 0 && shine < 1 {
                    shineGradient(width: w, progress: shine)
                        .mask(wordmark(size: size, qs: [1, 1, 1, 1], dy: dy, masked: false))
                }
            }
            .clipShape(SheetShape(edgeY: edgeY, arch: arch))

            if p > 0 && p < 1 {
                SheetEdge(edgeY: edgeY, arch: arch)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: Color(red: 200 / 255, green: 205 / 255, blue: 212 / 255).opacity(0), location: 0),
                                .init(color: Color(red: 201 / 255, green: 206 / 255, blue: 214 / 255), location: 0.2),
                                .init(color: .white, location: 0.5),
                                .init(color: Color(red: 201 / 255, green: 206 / 255, blue: 214 / 255), location: 0.8),
                                .init(color: Color(red: 200 / 255, green: 205 / 255, blue: 212 / 255).opacity(0), location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
                    .shadow(color: Color(red: 220 / 255, green: 230 / 255, blue: 240 / 255).opacity(0.9), radius: 7)
                    .opacity(1 - min(1, max(0, (p - 0.75) / 0.25)))
            }
        }
        .frame(width: w, height: h)
    }

    /// "pop" over "up", each letter sliding up out of its own line.
    private func wordmark(size: CGSize, qs: [Double], dy: CGFloat, masked: Bool) -> some View {
        let wh = SheetLift.wordHeight
        let stackHeight = 12 + wh + SheetLift.wordGap + wh + 36
        let popTop = size.height / 2 - stackHeight / 2 + 12
        let upTop = popTop + wh + SheetLift.wordGap
        let popY = popTop + wh / 2 + SheetLift.popDrop
        let upY = upTop + wh / 2

        return ZStack {
            line(masked: masked) {
                HStack(spacing: 0) {
                    letter("p", q: qs[0])
                    letter("o", q: qs[1])
                    letter("p", q: qs[2])
                }
            }
            .position(x: size.width / 2, y: popY + dy)

            line(masked: masked) {
                letter("up", q: qs[3])
            }
            .position(x: size.width / 2, y: upY + dy)
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func line<V: View>(masked: Bool, @ViewBuilder _ content: () -> V) -> some View {
        let wh = SheetLift.wordHeight
        let base = content().frame(height: wh)
        if masked {
            base.mask(Rectangle().frame(height: wh + 4).offset(y: -8))
        } else {
            base
        }
    }

    private func letter(_ s: String, q: Double) -> some View {
        Text(s)
            .font(markFont)
            .tracking(SheetLift.tracking)
            .foregroundStyle(.white)
            .offset(y: SheetLift.wordHeight * CGFloat(1 - q))
    }

    private func shineGradient(width: CGFloat, progress: Double) -> some View {
        let x = lerp(-133, width + 133, SheetLift.easeOut(progress))
        let half: CGFloat = 60
        let silver = Color(red: 150 / 255, green: 158 / 255, blue: 170 / 255)
        return LinearGradient(
            stops: [
                .init(color: silver.opacity(0), location: 0),
                .init(color: silver.opacity(0.9), location: 0.45),
                .init(color: .white, location: 0.5),
                .init(color: silver.opacity(0.9), location: 0.55),
                .init(color: silver.opacity(0), location: 1),
            ],
            startPoint: UnitPoint(x: (x - half) / width, y: 0.5),
            endPoint: UnitPoint(x: (x + half) / width, y: 0.5)
        )
    }

    // MARK: Reduce Motion

    private func reducedMotion(size: CGSize) -> some View {
        let fadeIn = SheetLift.easeOut(SheetLift.segment(t, 0, SheetLift.rmFadeIn))
        let fadeOut = SheetLift.segment(t, SheetLift.rmFadeOutStart, SheetLift.rmFadeOut)
        return ZStack {
            Color.black
            wordmark(size: size, qs: [1, 1, 1, 1], dy: 0, masked: false)
                .opacity(fadeIn)
        }
        .opacity(1 - fadeOut)
    }
}

// MARK: - Shapes

/// The black sheet: full width from the top down to an arched bottom edge.
private struct SheetShape: Shape {
    var edgeY: CGFloat
    var arch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -10))
        path.addLine(to: CGPoint(x: rect.width, y: -10))
        path.addLine(to: CGPoint(x: rect.width, y: edgeY))
        path.addQuadCurve(to: CGPoint(x: 0, y: edgeY),
                          control: CGPoint(x: rect.width / 2, y: edgeY - 2 * arch))
        path.closeSubpath()
        return path
    }
}

/// Just the arched bottom edge, for the silver rim.
private struct SheetEdge: Shape {
    var edgeY: CGFloat
    var arch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: edgeY))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: edgeY),
                          control: CGPoint(x: rect.width / 2, y: edgeY - 2 * arch))
        return path
    }
}

#Preview {
    LaunchReveal {
        LinearGradient(colors: [.green, .teal], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
