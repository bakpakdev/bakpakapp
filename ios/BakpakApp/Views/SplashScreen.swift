import SwiftUI

// MARK: - Tunable constants (1:1 with Figma Make prototype)

private enum SplashTiming {
    /// Prototype uses 112 on a 360pt canvas; ~88 keeps the same proportions on phone.
    static let fontSize: CGFloat = 88
    static let lineHeight: CGFloat = 1.12
    static var wordHeight: CGFloat { fontSize * lineHeight }
    static let wordGap: CGFloat = -8
    /// Prototype final drop of assembled "pop" toward "up".
    static let finalPopDrop: CGFloat = 22

    static let ballSize: CGFloat = 44
    static let ballStartOffsetY: CGFloat = 110
    /// CSS scaleX / scaleY on spread.
    static let ballSpreadScaleX: CGFloat = 2.7
    static let ballSpreadScaleY: CGFloat = 0.78

    // Prototype timeline (ms → s): 80, +400, +240, then letters…
    static let tBallUp: Double = 0.08
    static let tBallSpread: Double = 0.48
    static let tLetters: Double = 0.72
    static let tLetter1: Double = 0.76
    static let tLetter2: Double = 0.86
    static let tLetter3: Double = 0.96
    static let tDone: Double = 1.30
    static let tFinish: Double = 1.95

    static let ballUpDuration: Double = 0.38
    static let ballUpOpacityDuration: Double = 0.18
    static let ballSpreadTransformDuration: Double = 0.20
    static let ballSpreadOpacityDuration: Double = 0.16
    static let ballSpreadOpacityDelay: Double = 0.04
    static let upOpacityDuration: Double = 0.24
    static let upScaleDuration: Double = 0.34
    static let letterMoveDuration: Double = 0.30
    static let letterOpacityDuration: Double = 0.14
    static let finalDropDuration: Double = 0.38

    static let reduceMotionFade: Double = 0.25
    static let reduceMotionHold: Double = 0.40
}

// MARK: - Splash Screen

/// Matches the Figma Make Animated Splash Prototype motion, with the main app
/// deferred until after this finishes (keeps it smooth).
struct SplashScreen: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var ballOffsetY: CGFloat = SplashTiming.ballStartOffsetY
    @State private var ballScaleX: CGFloat = 0.01
    @State private var ballScaleY: CGFloat = 0.01
    @State private var ballOpacity: Double = 0

    @State private var upOpacity: Double = 0
    @State private var upScale: CGFloat = 0.82

    @State private var letter1Y: CGFloat = 0
    @State private var letter2Y: CGFloat = 0
    @State private var letter3Y: CGFloat = 0
    @State private var letter1Opacity: Double = 0
    @State private var letter2Opacity: Double = 0
    @State private var letter3Opacity: Double = 0

    @State private var popDrop: CGFloat = 0
    @State private var reduceMotionOpacity: Double = 0
    @State private var didStart = false
    @State private var workItems: [DispatchWorkItem] = []

    private var letterNestY: CGFloat { SplashTiming.wordHeight + SplashTiming.wordGap }
    private let markFont = Theme.syne(SplashTiming.fontSize, weight: .heavy)
    private let tracking: CGFloat = -0.02 * SplashTiming.fontSize

    /// Prototype layout geometry.
    private var popTop: CGFloat { 12 }
    private var upTop: CGFloat { popTop + SplashTiming.wordHeight + SplashTiming.wordGap }
    private var ballCenterY: CGFloat { upTop + SplashTiming.wordHeight / 2 }
    private var stackHeight: CGFloat { upTop + SplashTiming.wordHeight + 36 }
    private let stackWidth: CGFloat = 300

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if reduceMotion {
                finalWordmark
                    .opacity(reduceMotionOpacity)
            } else {
                animatedWordmark
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            start()
        }
        .onDisappear {
            workItems.forEach { $0.cancel() }
            workItems.removeAll()
        }
    }

    // MARK: Layout (mirrors prototype absolute stack)

    private var animatedWordmark: some View {
        ZStack(alignment: .top) {
            // Ball — sits on the vertical center of "up", then scaleX/scaleY spreads.
            Circle()
                .fill(Color.white)
                .frame(width: SplashTiming.ballSize, height: SplashTiming.ballSize)
                .shadow(color: Color.white.opacity(0.18), radius: 12)
                .scaleEffect(x: ballScaleX, y: ballScaleY)
                .opacity(ballOpacity)
                .offset(y: ballOffsetY)
                .position(x: stackWidth / 2, y: ballCenterY)

            // "up"
            Text("up")
                .font(markFont)
                .tracking(tracking)
                .foregroundStyle(.white)
                .opacity(upOpacity)
                .scaleEffect(upScale)
                .position(x: stackWidth / 2, y: upTop + SplashTiming.wordHeight / 2)

            // "pop" letters — rise independently, then the group drops on done.
            HStack(spacing: 0) {
                letterView("p", offsetY: letter1Y, opacity: letter1Opacity)
                letterView("o", offsetY: letter2Y, opacity: letter2Opacity)
                letterView("p", offsetY: letter3Y, opacity: letter3Opacity)
            }
            .offset(y: popDrop)
            .position(x: stackWidth / 2, y: popTop + SplashTiming.wordHeight / 2)
        }
        .frame(width: stackWidth, height: stackHeight)
    }

    private var finalWordmark: some View {
        VStack(spacing: SplashTiming.wordGap) {
            Text("pop").font(markFont).tracking(tracking)
            Text("up").font(markFont).tracking(tracking)
        }
        .foregroundStyle(.white)
        .offset(y: SplashTiming.finalPopDrop / 2)
    }

    private func letterView(_ text: String, offsetY: CGFloat, opacity: Double) -> some View {
        Text(text)
            .font(markFont)
            .tracking(tracking)
            .foregroundStyle(.white)
            .opacity(opacity)
            .offset(y: offsetY)
    }

    // MARK: Timeline (same beats as the React prototype)

    private func start() {
        if reduceMotion {
            withAnimation(.easeOut(duration: SplashTiming.reduceMotionFade)) {
                reduceMotionOpacity = 1
            }
            schedule(after: SplashTiming.reduceMotionFade + SplashTiming.reduceMotionHold) {
                onFinish()
            }
            return
        }

        // Reset to init
        ballOffsetY = SplashTiming.ballStartOffsetY
        ballScaleX = 0.01
        ballScaleY = 0.01
        ballOpacity = 0
        upOpacity = 0
        upScale = 0.82
        letter1Y = letterNestY
        letter2Y = letterNestY
        letter3Y = letterNestY
        letter1Opacity = 0
        letter2Opacity = 0
        letter3Opacity = 0
        popDrop = 0

        // Prototype cubic-beziers
        let ballUpCurve = Animation.timingCurve(0.34, 1.56, 0.64, 1, duration: SplashTiming.ballUpDuration)
        let letterCurve = Animation.timingCurve(0.34, 1.5, 0.64, 1, duration: SplashTiming.letterMoveDuration)
        let upScaleCurve = Animation.timingCurve(0.34, 1.5, 0.64, 1, duration: SplashTiming.upScaleDuration)
        let doneCurve = Animation.timingCurve(0.34, 1.5, 0.64, 1, duration: SplashTiming.finalDropDuration)

        // 1) ball-up — 380ms overshoot spring + faster opacity
        schedule(after: SplashTiming.tBallUp) {
            withAnimation(ballUpCurve) {
                ballOffsetY = 0
                ballScaleX = 1
                ballScaleY = 1
            }
            withAnimation(.easeOut(duration: SplashTiming.ballUpOpacityDuration)) {
                ballOpacity = 1
            }
        }

        // 2) ball-spread — scaleX 2.7 / scaleY 0.78, then opacity fades slightly after
        schedule(after: SplashTiming.tBallSpread) {
            withAnimation(.easeOut(duration: SplashTiming.ballSpreadTransformDuration)) {
                ballScaleX = SplashTiming.ballSpreadScaleX
                ballScaleY = SplashTiming.ballSpreadScaleY
            }
            withAnimation(
                .easeOut(duration: SplashTiming.ballSpreadOpacityDuration)
                .delay(SplashTiming.ballSpreadOpacityDelay)
            ) {
                ballOpacity = 0
            }
            // "up" appears as the ball spreads into it
            withAnimation(.easeOut(duration: SplashTiming.upOpacityDuration)) {
                upOpacity = 1
            }
            withAnimation(upScaleCurve) {
                upScale = 1
            }
        }

        // 3) Letters fire out of "up" with 100ms stagger
        schedule(after: SplashTiming.tLetter1) {
            withAnimation(letterCurve) { letter1Y = 0 }
            withAnimation(.easeOut(duration: SplashTiming.letterOpacityDuration)) { letter1Opacity = 1 }
        }
        schedule(after: SplashTiming.tLetter2) {
            withAnimation(letterCurve) { letter2Y = 0 }
            withAnimation(.easeOut(duration: SplashTiming.letterOpacityDuration)) { letter2Opacity = 1 }
        }
        schedule(after: SplashTiming.tLetter3) {
            withAnimation(letterCurve) { letter3Y = 0 }
            withAnimation(.easeOut(duration: SplashTiming.letterOpacityDuration)) { letter3Opacity = 1 }
        }

        // 4) Assembled "pop" drops closer to "up"
        schedule(after: SplashTiming.tDone) {
            withAnimation(doneCurve) {
                popDrop = SplashTiming.finalPopDrop
            }
        }

        // 5) Hold completed logo, then hand off
        schedule(after: SplashTiming.tFinish) {
            onFinish()
        }
    }

    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        let item = DispatchWorkItem(block: work)
        workItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

#Preview {
    SplashScreen(onFinish: {})
}
