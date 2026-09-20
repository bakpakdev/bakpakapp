import SwiftUI

struct RankBadgeIcon: View {
    let campus: BadgeCampusTheme
    let tier: RankTier
    let unlocked: Bool
    var isCurrent: Bool = false
    var size: CGFloat = 52

    private var shouldAnimate: Bool { unlocked && tier == .ultimate }
    private var iconName: String { unlocked ? tier.iconSystemName : campus.motifSystemName }

    var body: some View {
        ZStack {
            if unlocked && (tier == .diamond || tier == .elite || tier == .ultimate) {
                glowBlob
                    .blur(radius: size * 0.18)
                    .scaleEffect(1.08)
                    .opacity(tier == .ultimate ? 0.45 : 0.28)
            }

            chrome

            Image(systemName: iconName)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(iconColor)

            if unlocked && tier >= .gold {
                Image(systemName: campus.motifSystemName)
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundStyle(motifAccent)
                    .offset(y: -size * 0.34)
            }

            if unlocked && (tier == .diamond || tier == .elite || tier == .ultimate) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 2.5, height: 2.5)
                        .offset(x: size * (0.18 + CGFloat(i) * 0.05), y: -size * (0.12 + CGFloat(i) * 0.08))
                }
            }

            if !unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .offset(x: size * 0.28, y: size * 0.28)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if isCurrent {
                Circle()
                    .stroke(campus.secondary.opacity(0.95), lineWidth: 2)
                    .padding(-4)
            }
        }
        .scaleEffect(isCurrent ? 1.12 : 1)
        .grayscale(unlocked ? 0 : 0.9)
        .opacity(unlocked ? 1 : 0.42)
        .modifier(UltimateRankEffect(enabled: shouldAnimate, glow: campus.primary))
    }

    @ViewBuilder
    private var glowBlob: some View {
        switch tier {
        case .diamond:
            DiamondBadgeShape().fill(campus.primary)
        case .elite:
            EliteCrestShape().fill(campus.primary)
        default:
            UltimateCrestShape().fill(campus.primary)
        }
    }

    @ViewBuilder
    private var chrome: some View {
        let fills = fillColors
        let stroke = strokeColor
        let width = strokeWidth
        let gradient = LinearGradient(colors: fills, startPoint: .topLeading, endPoint: .bottomTrailing)
        let edge = LinearGradient(
            colors: [Color.white.opacity(0.55), stroke.opacity(0.25), stroke],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        switch tier {
        case .bronze, .silver:
            Circle()
                .fill(gradient)
                .overlay(Circle().stroke(stroke, lineWidth: width))
        case .gold:
            Circle()
                .fill(gradient)
                .overlay(Circle().stroke(edge, lineWidth: width))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1).padding(4))
        case .platinum:
            ShieldBadgeShape()
                .fill(gradient)
                .overlay(ShieldBadgeShape().stroke(edge, lineWidth: width))
        case .diamond:
            DiamondBadgeShape()
                .fill(gradient)
                .overlay(DiamondBadgeShape().stroke(edge, lineWidth: width))
                .overlay(DiamondBadgeShape().stroke(Color.white.opacity(0.35), lineWidth: 1).padding(5))
        case .elite:
            EliteCrestShape()
                .fill(gradient)
                .overlay(EliteCrestShape().stroke(edge, lineWidth: width))
        case .ultimate:
            UltimateCrestShape()
                .fill(gradient)
                .overlay(UltimateCrestShape().stroke(edge, lineWidth: width))
                .overlay(UltimateCrestShape().stroke(Color.white.opacity(0.35), lineWidth: 1).padding(4))
        }
    }

    private var fillColors: [Color] {
        guard unlocked else { return [Color.white.opacity(0.08), Color.white.opacity(0.05)] }
        switch tier {
        case .bronze:
            return [Color(hex: "#7C5A3C"), Color(hex: "#4E3A28")]
        case .silver:
            return [Color(hex: "#D0D4DA"), Color(hex: "#8C929A")]
        case .gold:
            return [campus.primary.opacity(0.92), Color(hex: "#D4AF37")]
        case .platinum:
            return [campus.primary, Color(hex: "#E5EAF1")]
        case .diamond, .elite, .ultimate:
            return [campus.primary, campus.secondary]
        }
    }

    private var strokeColor: Color {
        guard unlocked else { return Color.white.opacity(0.14) }
        switch tier {
        case .bronze, .silver:
            return campus.primary.opacity(0.75)
        case .gold, .platinum:
            return campus.primary
        case .diamond, .elite, .ultimate:
            return campus.secondary
        }
    }

    private var strokeWidth: CGFloat {
        switch tier {
        case .bronze, .silver: return 1
        case .gold, .platinum: return 1.6
        default: return 2
        }
    }

    private var iconColor: Color {
        guard unlocked else { return Color.white.opacity(0.35) }
        switch tier {
        case .bronze: return Color(hex: "#E8D5B5").opacity(0.85)
        case .silver: return Color.white.opacity(0.9)
        case .gold, .platinum: return campus.secondary
        case .diamond, .elite, .ultimate: return Color.white
        }
    }

    private var motifAccent: Color {
        switch tier {
        case .gold, .platinum: return campus.secondary.opacity(0.9)
        default: return campus.secondary
        }
    }
}

struct RankTierLabel: View {
    let tier: RankTier
    let campus: BadgeCampusTheme
    var unlocked: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            if unlocked && tier >= .diamond {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .bold))
            }
            Text(tier.displayName)
                .font(Theme.syne(11, weight: weight))
        }
        .foregroundStyle(color)
    }

    private var weight: Font.Weight {
        switch tier {
        case .bronze, .silver: return .medium
        case .gold, .platinum: return .semibold
        case .diamond, .elite, .ultimate: return .bold
        }
    }

    private var color: Color {
        guard unlocked else { return Color.white.opacity(0.35) }
        switch tier {
        case .bronze, .silver: return Color.white.opacity(0.55)
        case .gold, .platinum: return Color.white.opacity(0.85)
        case .diamond, .elite, .ultimate: return campus.secondary
        }
    }
}

private struct UltimateRankEffect: ViewModifier {
    let enabled: Bool
    let glow: Color
    @State private var on = false

    func body(content: Content) -> some View {
        Group {
            if enabled {
                content
                    .overlay {
                        GeometryReader { geo in
                            LinearGradient(
                                colors: [.clear, Color.white.opacity(0.55), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * 0.42, height: geo.size.height * 1.35)
                            .offset(x: on ? geo.size.width * 0.85 : -geo.size.width * 0.45)
                            .blendMode(.plusLighter)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .allowsHitTesting(false)
                    }
                    .shadow(color: glow.opacity(on ? 0.75 : 0.28), radius: on ? 14 : 6)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.7).repeatForever(autoreverses: true)) {
                            on = true
                        }
                    }
            } else {
                content
            }
        }
    }
}

private struct ShieldBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + rect.height * 0.16))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.minY + rect.height * 0.52))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY * 0.78)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + 1, y: rect.minY + rect.height * 0.52),
            control: CGPoint(x: rect.minX, y: rect.maxY * 0.78)
        )
        p.addLine(to: CGPoint(x: rect.minX + 1, y: rect.minY + rect.height * 0.16))
        p.closeSubpath()
        return p
    }
}

private struct DiamondBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.08
        let r = rect.insetBy(dx: inset, dy: inset)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct EliteCrestShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let wing = rect.width * 0.14
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - wing, y: rect.minY + rect.height * 0.18))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - wing, y: rect.minY + rect.height * 0.62))
        p.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - wing * 0.4, y: rect.maxY * 0.82)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + wing, y: rect.minY + rect.height * 0.62),
            control: CGPoint(x: rect.minX + wing * 0.4, y: rect.maxY * 0.82)
        )
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + wing, y: rect.minY + rect.height * 0.18))
        p.closeSubpath()
        return p
    }
}

private struct UltimateCrestShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX
        let cy = rect.midY
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.58
        var p = Path()
        for i in 0..<8 {
            let angle = (Double(i) / 8.0) * .pi * 2 - .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: cx + CGFloat(cos(angle)) * r, y: cy + CGFloat(sin(angle)) * r)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}

struct BadgeUnlockToast: View {
    let unlock: RankUnlock
    let onDismiss: () -> Void
    @Environment(\.campusTheme) private var campusTheme

    var body: some View {
        VStack(spacing: 14) {
            RankBadgeIcon(
                campus: unlock.campus,
                tier: unlock.tier,
                unlocked: true,
                isCurrent: true,
                size: 78
            )
            Text(unlock.name)
                .font(Theme.syne(18, weight: .bold))
                .foregroundStyle(campusTheme.textPrimary)
            Text(unlock.campus.tagline)
                .font(Theme.syne(13, weight: .medium))
                .foregroundStyle(campusTheme.textMuted)
                .multilineTextAlignment(.center)
            Button(action: onDismiss) {
                Text("Nice!")
                    .font(Theme.syne(14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(unlock.campus.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(BouncyButtonStyle(pressedScale: 0.97))
        }
        .padding(22)
        .background(campusTheme.surface.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(unlock.campus.primary.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 32)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
    }
}
